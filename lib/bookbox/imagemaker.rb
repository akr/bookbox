module BookBox
end

class BookBox::ImageMaker < ::Dep

  BDIR = %r{\A(?<dir>/?(?:[^/]+/)*)\.bookbox/}
  PDIR = %r{\A(?<dir>/?(?:[^/]+/)*)}
  PSTEM = /(?<stem>-*[0-9]+)/
  PCOLORMODE = /(?<colormode>[cgm])/
  PBASE = %r{(?<base>(small|fullsize))}

  source %r{#{PDIR}scan\.json\z}

  rule(%r{#{PDIR}out#{PSTEM}\.pnm\z}) {|match, out_fn|
    dir = match[:dir]
    unless file_stat(out_fn)
      raise ArgumentError, "no source image: #{out_fn}"
    end
    scan_params = hashtree_nested(read_json("#{dir}scan.json"))
    scan_params["pages"][File.basename(out_fn)] || {}
  }

  primitive(:image_stem_list) {|dir|
    result = []
    Dir.entries(dir).each {|f|
      next if f !~ %r{#{PDIR}out#{PSTEM}\.pnm\z}mo
      result << $~["stem"]
    }
    result.sort_by {|stem| strnumsortkey(stem) }
  }

  rule(%r{#{BDIR}fullsize#{PSTEM}_c\.pnm\z}, '\k<dir>out\k<stem>.pnm') {|match, fullsize_fn, (out_fn, out_att)|
    angle = out_att["rotate"] || 0
    run_pipeline out_fn, fullsize_fn, make_flip_command(angle)
    out_att = out_att.dup
    out_att.delete "rotate"
    out_att
  }

  rule(%r{#{PDIR}fullsize#{PSTEM}_#{PCOLORMODE}\.png\z},
         '\k<dir>fullsize\k<stem>_\k<colormode>.pnm') {|match, png_fn, (pnm_fn, pnm_att)|
    dpi = pnm_att["dpi"] || 72
    dpm = (dpi / 25.4 * 1000).round
    run_pipeline pnm_fn, png_fn, %W[pnmtopng -phys #{dpm} #{dpm} 1]
  }

  rule(%r{#{BDIR}small#{PSTEM}_c\.pnm\z}, '\k<dir>out\k<stem>.pnm') {|match, scf, (out_fn, out_att)|
    angle = out_att["rotate"] || 0
    run_pipeline out_fn, scf, make_flip_command(angle), ["pnmscale", "-width=80"]
    out_att = out_att.dup
    out_att.delete "rotate"
    out_att
  }

  rule(%r{#{PDIR}#{PBASE}#{PSTEM}_g\.pnm\z}, '\k<dir>\k<base>\k<stem>_c.pnm') {|match, sgf, (scf, att)|
    run_pipeline scf, sgf, ["ppmtopgm"]
    att
  }

  rule(%r{#{PDIR}small#{PSTEM}_m\.pnm\z}, '\k<dir>small\k<stem>_g.pnm') {|match, smf, (sgf, att)|
    run_pipeline sgf, smf, %w[pgmtopbm -threshold -value 0.7]
    att
  }

  rule(%r{#{PDIR}fullsize#{PSTEM}_m\.pnm\z}, '\k<dir>fullsize\k<stem>_g.pnm') {|match, smf, (sgf, att)|
    run_pipeline sgf, smf, %w[pgmtopbm -threshold]
    att
  }

  rule(%r{#{PDIR}(?<basename>[^/]+)\.png\z}, '\k<dir>\k<basename>.pnm') {|match, png, (pnm, att)|
    run_pipeline pnm, png, ["pnmtopng"]
    att
  }

  ambiguous(%r{#{PDIR}fullsize#{PSTEM}_#{PCOLORMODE}\.png\z}, %r{#{PDIR}(?<basename>[^/]+)\.png\z})

  phony(:all_fullsize_images) { image_stem_list(".").each {|stem| make("fullsize#{stem}_c.png") } }
  phony(:all_color_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_c.png") } }
  phony(:all_gray_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_g.png") } }
  phony(:all_mono_thumbnails) { image_stem_list(".").each {|stem| make("small#{stem}_m.png") } }
  phony(:all_thumbnails) { all_color_thumbnails; all_gray_thumbnails; all_mono_thumbnails }
  phony(:all_images) {
    %w[small fullsize].each {|base|
      image_stem_list(".").each {|stem|
        %w[c g m].each {|colormode|
          make(File.realdirpath(Dir.pwd)+"/.bookbox/#{base}#{stem}_#{colormode}.png")
        }
      }
    }
  }

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