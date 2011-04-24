require 'pp'
require 'open3'
require 'json'
require 'thread'
require 'fileutils'
require 'pathname'

class Dep
  def self.start
    yield self.new
  end

  def initialize
    @verbose = defined?($opt_verbose) ? $opt_verbose : false
    @internal_memo = {}
    @cwd_pat = %r{\A#{Regexp.escape Dir.pwd}/}
  end

  attr_accessor :verbose

  def vmesg(mesg)
    STDERR.print "#{mesg}\n" if @verbose
  end

  def internal_memo(obj, meth, *args)
    key = [obj, meth, args]
    trs = Thread.current[:dep_internal_memo_transaction]
    if trs
      trs.reverse_each {|tr|
        return tr[key] if tr.include?(key)
      }
    end
    if @internal_memo.include?(key)
      return @internal_memo[key]
    end
    v = obj.send(meth, *args)
    if trs && trs.last
      trs.last[key] = v
    else
      @internal_memo[key] = v
    end
  end

  def internal_memo_transaction
    Thread.current[:dep_internal_memo_transaction] ||= []
    trs = Thread.current[:dep_internal_memo_transaction]
    new_tr = {}
    trs.push new_tr
    begin
      res = yield
    ensure
      trs.pop
      Thread.current[:dep_internal_memo_transaction] = nil if trs.empty?
    end
    if !trs.empty?
      trs.last.update new_tr
    else
      @internal_memo.update new_tr
    end
    res
  end

  def internal_memo_guard
    internal_memo_transaction {
      res = yield
      if !res
        Thread.current[:dep_internal_memo_transaction].last.clear
      end
      res
    }
  end

  def external_memo(log_filename, mesg_filename, &block)
    begin
      old_history = Thread.current[:dep_external_memo_history]
      Thread.current[:dep_external_memo_history] = []
      external_memo2(log_filename, mesg_filename, &block)
    ensure
      Thread.current[:dep_external_memo_history] = old_history
    end
  end

  def external_memo2(log_filename, mesg_filename)
    vmesg "try: #{mesg_filename}"
    log_dir = log_filename.dirname
    log_dir.mkpath if !log_dir.directory?
    log_filename.open(File::RDWR|File::CREAT, 0644) {|log_io|
      log_io.flock(File::LOCK_EX)
      if ((if 0 < log_io.stat.size
             true
           else
             reason = "no build log"
             false
           end) &&
          (log = decode_pathname(Marshal.load(log_io), log_dir)) &&
          log["history"].all? {|type, meth, args, res|
            if type == :update
              res2 = self.send(meth, *args)
              success = res2 == res
            else
              res2 = nil
              success = internal_memo_guard {
                res2 = self.send(meth, *args)
                res2 == res
              }
            end
            if success
              true
            else
              reason = self.respond_to?("#{meth}_inspect") ?
                       self.send("#{meth}_inspect", args) :
                       "#{meth}(#{args.map {|a| a.inspect }.join(', ')})"
              reason += "\nold value: #{res.inspect}\nnew value: #{res2.inspect}"
              false
            end
          })
        vmesg "skip: #{mesg_filename}"
        log["result"]
      else
        vmesg reason.gsub(/^/) { "build start: #{mesg_filename} because " }
        begin
          old_history = Thread.current[:dep_external_memo_history]
          Thread.current[:dep_external_memo_history] = []
          result = yield
          history = Thread.current[:dep_external_memo_history]
          h = {
            "history" => history,
            "result" => result
          }
          log_io.rewind
          log_io.write Marshal.dump(encode_pathname(h, log_dir))
          log_io.flush
          log_io.truncate(log_io.pos)
        ensure
          Thread.current[:dep_external_memo_history] = old_history
        end
        vmesg "build done: #{mesg_filename}"
        result
      end
    }
  end

  def external_memo_log(type, meth, args)
    res = self.send(meth, *args)
    history = Thread.current[:dep_external_memo_history]
    if history
      history << [type, meth, args, res]
    end
    res
  end

  def primitive_wrapper(type, pname, *args)
    external_memo_log(type, :primitive_wrapper1, [pname, *args])
  end

  def primitive_wrapper1_inspect(args)
    pname, *args = args
    "#{pname}(#{args.map {|a| a.inspect }.join(', ')})"
  end
  def primitive_wrapper1(pname, *args)
    begin
      old_history = Thread.current[:dep_external_memo_history]
      Thread.current[:dep_external_memo_history] = nil
      internal_memo(self, "#{pname}_body", *args)
    ensure
      Thread.current[:dep_external_memo_history] = old_history
    end
  end

  def self.primitive(pname, &block)
    pname = pname.to_s
    define_method("#{pname}_body", &block)
    eval "def #{pname}(*args) primitive_wrapper(:update, #{pname.dump}, *args) end"
  end

  def self.check_primitive(pname, &block)
    pname = pname.to_s
    define_method("#{pname}_body", &block)
    eval "def #{pname}(*args) primitive_wrapper(:check, #{pname.dump}, *args) end"
  end

  def self.rule(output_pattern, *input_repl_list, &block)
    @rules ||= []
    @rules << [output_pattern, :rule, input_repl_list, block]
  end

  def self.source(filename_pattern, &block)
    @rules ||= []
    @rules << [filename_pattern, :source, block]
  end

  def self.get_rules
    @rules ||= []
    @rules
  end

  def self.ambiguous(top_prio_pattern, *rest_patterns)
    @amb_patterns ||= {}
    all_patterns = [top_prio_pattern, *rest_patterns]
    key = all_patterns.sort_by {|pat| pat.source }
    @amb_patterns[key] = top_prio_pattern
  end

  def self.get_ambiguous_patterns(*patterns)
    @amb_patterns ||= {}
    key = patterns.sort_by {|pat| pat.source }
    @amb_patterns[key]
  end

  def make(filename)
    filename = Pathname.new(filename) unless Pathname === filename
    external_memo_log(:update, :make1, [filename])
  end

  def encode_pathname(obj, directory)
    m = Marshal.dump(obj)
    Marshal.load(m, lambda {|o|
      if Pathname === o
        o.relative_path_from(directory)
      else
        o
      end
    })
  end

  def decode_pathname(obj, directory)
    m = Marshal.dump(obj)
    Marshal.load(m, lambda {|o|
      if Pathname === o
        directory+o
      else
        o
      end
    })
  end

  def make1_inspect(args)
    filename, = args
    "make(#{filename.inspect}"
  end
  def make1(filename)
    internal_memo(self, :make2, filename)
  end

  def find_rule(filename)
    rules = self.class.get_rules
    matched = []
    rules.each {|output_pattern, rule_type, input_repl_list, block|
      if output_pattern =~ filename.to_s
        matched << [output_pattern, rule_type, input_repl_list, block]
      end
    }
    if matched.empty?
      raise ArgumentError, "no rule for #{filename}"
    end
    if matched.length == 1
      choosen_rule = matched[0]
    else
      prio_pat = self.class.get_ambiguous_patterns(*matched.map {|pat,| pat })
      if prio_pat
        choosen_rule = matched.find {|pat,| pat == prio_pat }
      else
        choosen_rule = matched[0]
        choosen_output_pattern, choosen_rule_type, = choosen_rule
        s1 = choosen_output_pattern.inspect
        s2 = matched[1..-1].map {|pat,| pat }.map {|pat| pat.inspect}.join(", ")
        warn "ambiguous patterns.  #{s1} choosen.  #{s2} ignored."
      end
    end
    choosen_rule
  end

  def make2(filename)
    rule = find_rule(filename)
    choosen_output_pattern, choosen_rule_type, = rule
    #p [filename, choosen_rule_type]
    case choosen_rule_type
    when :source
      make_source(filename, rule)
    when :rule
      d, f = filename.split
      path = d + ".dep-#{f}.marshal"
      external_memo(path, filename.sub(@cwd_pat, '')) { make_rule(filename, rule) }
    else
      raise "unexpected rule type: #{choosen_rule_type}"
    end
  end

  def make_source(filename, rule)
    choosen_output_pattern, choosen_rule_type, choosen_block = rule
    if choosen_block
      res = self.instance_exec(choosen_output_pattern.match(filename.to_s), filename, &choosen_block)
      file_stat(filename)
    else
      res = file_stat(filename)
    end
    res
  end

  def make_rule(filename, choosen_rule)
    choosen_output_pattern, choosen_rule_type, choosen_input_repl_list, choosen_block = choosen_rule
    args = choosen_input_repl_list.map {|repl|
      fn = Proc === repl ? filename.sub(choosen_output_pattern, &repl) :
                           filename.sub(choosen_output_pattern, repl)
      r = make(fn)
      file_stat(fn)
      [fn, r]
    }
    res = self.instance_exec(choosen_output_pattern.match(filename.to_s), filename, *args, &choosen_block)
    file_stat(filename)
    res
  end

  check_primitive(:file_stat) {|filename|
    begin
      st = filename.stat
    rescue Errno::ENOENT
      return nil
    end
    [st.mtime, st.size]
  }

  def read_json(filename)
    file_stat(filename)
    filename.open {|f| JSON.load(f) }
  end

  def run_pipeline(input_filename, output_filename, *commands)
    status_list = run_pipeline1(input_filename.to_s, output_filename.to_s, *commands)
    status_list.each_with_index {|s, i|
      if !s.success?
        commandline = commands[i]
        raise ArgumentError, "command failed: #{commandline.inspect}"
      end
    }
    nil
  end

  def run_pipeline1(input_filename, output_filename, *commands)
    commands = commands.compact
    if commands.empty?
      FileUtils.cp input_filename, output_filename
      []
    else
      commands[0] = commands[0] + [input_filename]
      commands[-1] = commands[-1] + [:out => output_filename]
      Open3.pipeline(*commands)
    end
  end
end
