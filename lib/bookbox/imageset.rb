require 'open3'
require 'json'
require 'fileutils'

class ImageSet
  def initialize(dir)
    @dir = dir
    scan_json_path = "#{dir}/scan.json"
    if File.exist? scan_json_path
      @index_hash = File.open(scan_json_path) {|f| JSON.load(f) }
    else
      @index_hash = {}
    end
    @index_hash["list"] ||= image_filenames
    @index_hash["i"] ||= {}
  end

  def mktmppath(suffix='')
    n = 1
    begin
      path = "#{@dir}/tmp#{n}#{suffix}"
      f = File.open(path, File::CREAT|File::WRONLY|File::EXCL)
    rescue Errno::EEXIST
      n += 1
      retry
    end
    f.close
    if block_given?
      begin
        yield path
      ensure
        File.delete path
      end
    else
      path
    end
  end

  def partgen(dest)
    dest2 = dest + ".part"
    yield dest2
    File.rename dest2, dest
  end

  def image_dir
    @dir
  end

  def image_filenames
    fs = Dir.entries(@dir)
    fs = fs.reject {|f|
      f !~ /\Aout/ || f !~ /\.(pnm|ppm|pgm|pbm|tiff?)\z/
    }
    fs.sort_by {|f| strnumsortkey(f) }
  end

  def thum_filenames
    image_filenames.map {|f|
      f.sub(/\Aout/, 'bb-thum').sub(/\.(pnm|ppm|pgm|pbm|tiff?)\z/, '.png')
    }
  end

  def make(filename)
    if %r{/} =~ filename
      raise ArgumentError, "slash contained filename: #{filename.inspect}"
    end
    path = @dir + "/" + filename
    return path if File.exist?(path)
    rule = @index_hash["i"][filename]
    if !rule
      raise ArgumentError, "no rule for #{filename.inspect}"
    end
    run(rule, path)
    path
  end

  def run(rule, dest)
    #p [rule, dest]
    case rule[0]
    when 'make'
      path0 = make(rule[1])
      partgen(dest) {|dest2|
        FileUtils.cp path0, dest2
      }
      {}
    when "flip"
      mktmppath {|tmppath|
        h = run(rule[2], tmppath)
        partgen(dest) {|dest2|
          system('pnmflip', "-"+rule[1], tmppath, :out => dest2)
        }
        h
      }
    when "resolution"
      dpi = rule[1]
      h = run(rule[2], dest)
      h['dpi'] = dpi
      h
    when "convert"
      case rule[1]
      when 'png'
        mktmppath {|tmppath|
          partgen(dest) {|dest2|
            h = run(rule[2], tmppath)
            commandline = ['pnmtopng']
            if h['dpi']
              # dot/inch -> dot/meter
              dpm = (h['dpi'] / 25.4 * 1000).round
              commandline.concat ['-phys', dpm.to_s, dpm.to_s, '1']
            end
            commandline << tmppath
            commandline << {:out => dest2}
            system(*commandline)
            h
          }
        }
      else
        raise ArgumentError, "unexpected format: #{rule[1].inspect}"
      end
    else
      raise ArgumentError, "unexpected rule type: #{rule[0].inspect}"
    end
  end
end

