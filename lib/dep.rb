require 'pp'
require 'open3'
require 'json'


class Dep
  def self.start
    yield self.new
  end

  def initialize
    @verbose = defined?($opt_verbose) ? $opt_verbose : false
    @internal_memo = {}
    @history = []
  end

  attr_accessor :verbose

  def internal_memo(obj, meth, *args)
    key = [obj, meth, args]
    imemo = @internal_memo
    if imemo.include? key
      imemo[key]
    else
      imemo[key] = obj.send(meth, *args)
    end
  end

  def internal_memo_guard
    old_imemo = @internal_memo.dup
    res = yield
    if !res
      @internal_memo = old_imemo
    end
    res
  end

  def external_memo(filename, mesg_filename=filename, &block)
    begin
      old_history = @history
      @history = []
      external_memo2(filename, mesg_filename, &block)
    ensure
      @history = old_history
    end
  end

  def external_memo2(log_filename, mesg_filename)
    STDERR.puts "try: #{mesg_filename}" if @verbose
    if ((if File.exist?(log_filename)
           true
         else
           reason = "no build log"
           false
         end) &&
        (log = File.open(log_filename) {|f| Marshal.load(f) }) &&
        log["history"].all? {|type, meth, args, res, mesg|
          if type == :gen
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
            reason = mesg || "#{meth}(#{args.map {|a| a.inspect }.join(', ')})"
            reason += "\nold value: #{res.inspect}\nnew value: #{res2.inspect}"
            false
          end
        })
      STDERR.puts "skip: #{mesg_filename}" if @verbose
      log["result"]
    else
      STDERR.puts reason.gsub(/^/) { "build start: #{mesg_filename} because " } if @verbose
      #STDERR.puts "build start: #{mesg_filename} because #{reason}" if @verbose
      @history = []
      result = yield
      history = @history
      h = {
        "history" => history,
        "result" => result
      }
      File.open(log_filename, "w") {|f| Marshal.dump(h, f) }
      STDERR.puts "build done: #{mesg_filename}" if @verbose
      result
    end
  end

  def external_memo_log(type, meth, args, mesg=nil)
    mesg ||= "#{meth}(#{args.map {|a| a.inspect }.join(', ')})"
    res = self.send(meth, *args)
    @history << [type, meth, args, res, mesg]
    res
  end

  def primitive_wrapper(type, pname, *args)
    mesg = "#{pname}(#{args.map {|a| a.inspect }.join(', ')})"
    external_memo_log(type, :primitive_wrapper1, [pname, *args], mesg)
  end

  def primitive_wrapper1(pname, *args)
    begin
      old_history = @history
      @history = nil
      internal_memo(self, "#{pname}_body", *args)
    ensure
      @history = old_history
    end
  end

  def self.primitive(pname, &block)
    pname = pname.to_s
    define_method("#{pname}_body", &block)
    eval "def #{pname}(*args) primitive_wrapper(:gen, #{pname.dump}, *args) end"
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
    external_memo_log(:gen, :make1, [filename], "make(#{filename.inspect})")
  end

  def make1(filename)
    internal_memo(self, :make2, filename)
  end

  def make2(filename)
    d, f = File.split(filename)
    path = File.join(d, ".dep-#{f}.marshal")
    external_memo(path, filename) { make3(filename) }
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
      raise ArgumentError, "no rule to make #{filename}"
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

  def self.phony(target_name, *input_filenames, &block)
    define_method(target_name) {
      args = input_filenames.map {|filename|
        r = make(filename)
        [filename, r]
      }
      self.instance_exec(*args, &block) if block
    }
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

  primitive(:read_json) {|filename|
    File.open(filename) {|f| JSON.load(f) }
  }

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
