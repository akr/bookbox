require 'dep'

module BookBox
end

class BookBox::ImageMaker < ::Dep

  DIR = %r{(?<dir>(?:[^/]+/)*)}
  STEM = /(?<stem>[-0-9]+)/

  source %r{\Ascan\.json\z}

  rule(%r{\Aout#{STEM}\.pnm\z}) {|match, out_fn|
    unless file_stat(out_fn)
      raise ArgumentError, "no source image: #{out_fn}"
    end
    scan_params = read_json("scan.json")
    scan_params[out_fn] || {}
  }

  primitive(:image_stem_list) {|dir|
    result = []
    Dir.entries(dir).each {|f|
      next if f !~ %r{\A#{DIR}out#{STEM}\.pnm\z}mo
      result << $~["stem"]
    }
    result.sort_by {|stem| strnumsortkey(stem) }
  }

  rule(%r{\A#{DIR}fullsize#{STEM}\.png\z}, '\k<dir>out\k<stem>.pnm') {|match, fullsize_fn, (out_fn, out_attr)|
    angle = out_attr["rotate"] || 0
    dpi = out_attr["dpi"] || 72
    dpm = (dpi / 25.4 * 1000).round
    run_pipeline out_fn, fullsize_fn, make_flip_command(angle), %W[pnmtopng -phys #{dpm} #{dpm} 1]
  }

  rule(%r{\A#{DIR}small#{STEM}_c\.pnm\z}, '\k<dir>out\k<stem>.pnm') {|match, scf, (out_fn, out_attr)|
    angle = out_attr["rotate"] || 0
    run_pipeline out_fn, scf, make_flip_command(angle), ["pnmscale", "-width=80"]
  }

  rule(%r{\A#{DIR}small#{STEM}_g\.pnm\z}, '\k<dir>small\k<stem>_c.pnm') {|match, sgf, (scf, _)|
    run_pipeline scf, sgf, ["ppmtopgm"]
  }

  rule(%r{\A#{DIR}small#{STEM}_m\.pnm\z}, '\k<dir>small\k<stem>_g.pnm') {|match, smf, (sgf, _)|
    run_pipeline sgf, smf, ["pgmtopbm"]
  }

  rule(%r{\A#{DIR}(?<basename>[^/]+)\.png\z}, '\k<dir>\k<basename>.pnm') {|match, png, (pnm, _)|
    run_pipeline pnm, png, ["pnmtopng"]
  }

  ambiguous(%r{\A#{DIR}fullsize#{STEM}\.png\z}, %r{\A#{DIR}(?<basename>[^/]+)\.png\z})

  phony(:all_fullsize_images) { image_stem_list(".").each {|stem| make("fullsize#{stem}.png") } }
  phony(:all_color_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_c.png") } }
  phony(:all_gray_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_g.png") } }
  phony(:all_mono_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_m.png") } }
  phony(:all_thumbnails) { all_color_thumbnails; all_gray_thumbnails; all_mono_thumbnails }
  phony(:all_images) { all_thumbnails; all_fullsize_images }

  def make_flip_command(angle)
    case angle
    when 0 then return nil
    when 90 then flip_arg = '-r90'
    when 180 then flip_arg = '-r180'
    when 270 then flip_arg = '-r270'
    else raise ArgumentError, "unexpected angle: #{angle.inspect}"
    end
    return ["pnmflip", flip_arg]
  end

end
