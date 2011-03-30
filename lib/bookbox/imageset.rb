require 'open3'

class ImageSet
  def initialize(dir)
    @dir = dir
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
    case filename
    when /\Aout/
      raise ArgumentError, "cannot generate source image: #{filename.inspect}"
    when %r{\Abb-thum(.*)\.png\z}
      out_filename = @dir + "/out#{$1}.tiff"
      thum_filename = @dir + "/#{filename}"
      Open3.pipeline(
        ['tifftopnm', out_filename, :err => "/dev/null"],
        "pnmscale -width=80",
        ['pnmtopng', :out => thum_filename])
    else
      raise ArgumentError, "unexpected filename: #{filename.inspect}"
    end
    path
  end
end

