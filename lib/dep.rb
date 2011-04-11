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
    tr = Thread.current[:dep_internal_memo_transaction]
    if tr && tr.include?(key)
      tr[key]
    elsif @internal_memo.include? key
      @internal_memo[key]
    else
      v = obj.send(meth, *args)
      if tr
        tr[key] = v
      else
        @internal_memo[key] = v
      end
    end
  end

  def internal_memo_transaction
    begin
      old_tr = Thread.current[:dep_internal_memo_transaction]
      Thread.current[:dep_internal_memo_transaction] = new_tr = {}
      res = yield
      if old_tr
        old_tr.update new_tr
      else
        @internal_memo.update new_tr
      end
      res
    ensure
      Thread.current[:dep_internal_memo_transaction] = old_tr
    end
  end

  def internal_memo_guard
    internal_memo_transaction {
      res = yield
      if !res
        Thread.current[:dep_internal_memo_transaction].clear
      end
      res
    }
  end

  def external_memo(log_filename, mesg_filename, &block)
    begin
      old_history = Thread.current[:dep_external_memo_history]
      old_directory = Thread.current[:dep_external_memo_directory]
      Thread.current[:dep_external_memo_history] = []
      Thread.current[:dep_external_memo_directory] = File.dirname(log_filename)
      external_memo2(log_filename, mesg_filename, &block)
    ensure
      Thread.current[:dep_external_memo_history] = old_history
      Thread.current[:dep_external_memo_directory] = old_directory
    end
  end

  def external_memo2(log_filename, mesg_filename)
    vmesg "try: #{mesg_filename}"
    log_dir = File.dirname(log_filename)
    FileUtils.mkdir_p(log_dir) if !File.directory?(log_dir)
    File.open(log_filename, File::RDWR|File::CREAT, 0644) {|log_io|
      log_io.flock(File::LOCK_EX)
      if ((if 0 < log_io.stat.size
             true
           else
             reason = "no build log"
             false
           end) &&
          (log = Marshal.load(log_io)) &&
          log["history"].all? {|type, meth, encoded_args, res|
            args = self.send("#{meth}_decode_args", encoded_args)
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
                       self.send("#{meth}_inspect", encoded_args) :
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
          log_io.write Marshal.dump(h)
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
      encoded_args = self.send("#{meth}_encode_args", args)
      history << [type, meth, encoded_args, res]
    end
    res
  end

  def primitive_wrapper(type, pname, *args)
    external_memo_log(type, :primitive_wrapper1, [pname, *args])
  end

  def primitive_wrapper1_encode_args(all_args)
    pname, *args = all_args
    args = self.send("#{pname}_encode_args", args)
    [pname, *args]
  end
  def primitive_wrapper1_decode_args(all_args)
    pname, *args = all_args
    args = self.send("#{pname}_decode_args", args)
    [pname, *args]
  end
  def primitive_wrapper1_inspect(encoded_args)
    pname, *args = encoded_args
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
    @rules << [output_pattern, input_repl_list, block]
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
    external_memo_log(:update, :make1, [filename])
  end

  def path2rel(path)
    directory = Thread.current[:dep_external_memo_directory]
    Pathname(path).relative_path_from(Pathname(directory)).to_s
  end
  def path2abs(path)
    directory = Thread.current[:dep_external_memo_directory]
    (Pathname(directory)+Pathname(path)).to_s
  end

  def make1_encode_args(args)
    filename, = args
    filename = path2rel(filename)
    [filename]
  end
  def make1_decode_args(args)
    filename, = args
    filename = path2abs(filename)
    [filename]
  end
  def make1_inspect(encoded_args)
    filename, = args
    "make(#{filename.inspect}"
  end
  def make1(filename)
    internal_memo(self, :make2, filename)
  end

  def make2(filename)
    d, f = File.split(filename)
    path = File.join(d, ".dep-#{f}.marshal")
    external_memo(path, filename.sub(@cwd_pat, '')) { make3(filename) }
  end

  def make3(filename)
    rules = self.class.get_rules
    matched = []
    rules.each {|output_pattern, input_repl_list, block|
      if output_pattern =~ filename
        matched << [output_pattern, input_repl_list, block]
      end
    }
    if matched.empty?
      raise ArgumentError, "no rule for #{filename}"
    end
    if matched.length == 1
      choosen_output_pattern, choosen_input_repl_list, choosen_block = matched[0]
    else
      prio_pat = self.class.get_ambiguous_patterns(*matched.map {|pat,| pat })
      if prio_pat
        choosen_output_pattern, choosen_input_repl_list, choosen_block =
          matched.find {|pat,| pat == prio_pat }
      else
        choosen_output_pattern, choosen_input_repl_list, choosen_block = matched[0]
        s1 = choosen_output_pattern.inspect
        s2 = matched[1..-1].map {|pat,| pat }.map {|pat| pat.inspect}.join(", ")
        warn "ambiguous patterns.  #{s1} choosen.  #{s2} ignored."
      end
    end
    args = choosen_input_repl_list.map {|repl|
      fn = Proc === repl ? filename.sub(choosen_output_pattern, &repl) :
                           filename.sub(choosen_output_pattern, repl)
      r = make(fn)
      file_stat(fn)
      [fn, r]
    }
    res = self.instance_exec(choosen_output_pattern.match(filename), filename, *args, &choosen_block)
    file_stat(filename)
    res
  end

  def file_stat_encode_args(args)
    filename, = args
    filename = path2rel(filename)
    [filename]
  end
  def file_stat_decode_args(args)
    filename, = args
    filename = path2abs(filename)
    [filename]
  end
  check_primitive(:file_stat) {|filename|
    begin
      st = File.stat(filename)
    rescue Errno::ENOENT
      return nil
    end
    [st.mtime, st.size]
  }

  def self.source(filename_pattern)
    rule(filename_pattern) {|match, filename|
      unless file_stat filename
        raise ArgumentError, "no source file: #{filename}"
      end
    }
  end

  def read_json(filename)
    file_stat(filename)
    File.open(filename) {|f| JSON.load(f) }
  end

  def run_pipeline(input_filename, output_filename, *commands)
    status_list = run_pipeline1(input_filename, output_filename, *commands)
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
