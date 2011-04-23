module BookBox
end

class BookBox::ImageMaker < ::Dep

  BDIR = %r{\A(?<dir>/?(?:[^/]+/)*)\.bookbox/}
  PDIR = %r{\A(?<dir>/?(?:[^/]+/)*)}
  PSTEM = /(?<stem>-*[0-9]+)/
  PCOLORMODE = /(?<colormode>[cgm])/
  PBASE = %r{(?<base>(small|fullsize))}

  source %r{#{PDIR}scan[0-9]*\.json\z}

  primitive(:glob) {|dir, pat|
    result = []
    dir.entries.each {|f|
      next if pat !~ f.basename.to_s
      result << f
    }
    result.sort_by {|f| strnumsortkey(f.to_s) }
    result.map {|f| dir + f }
  }

  def read_scan_json(dir)
    fs = glob(dir, /\Ascan[0-9]*\.json\z/)
    scan_json_path = Pathname.new("#{dir}/scan.json")
    if fs.include? scan_json_path
      fs.delete scan_json_path
      fs.unshift scan_json_path
    end
    result = {}
    fs.each {|f|
      result.update read_json(f)
    }
    result
  end

  source(%r{#{PDIR}out#{PSTEM}\.pnm\z}) {|match, out_fn|
    dir = Pathname.new(match[:dir])
    unless file_stat(out_fn)
      raise ArgumentError, "no source image: #{out_fn}"
    end
    scan_params = hashtree_nested(read_scan_json(dir))
    scan_params.fetch("pages", {}).fetch(out_fn.basename.to_s, {})
  }

  primitive(:image_stem_list) {|dir|
    result = []
    dir.entries.each {|f|
      next if %r{#{PDIR}out#{PSTEM}\.pnm\z}mo !~ f.to_s
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

  rule(%r{#{BDIR}stat\.js\z}) {|match, js_fn|
    dir = Pathname.new(match[:dir])
    stems = image_stem_list(dir)
    fs = []
    pages = {}
    stems.each_with_index {|stem, page|
      fn = Pathname.new("#{dir}.bookbox/small#{stem}_c.pnm")
      pages[fn.to_s] = page
      make(fn)
      file_stat(fn)
      fs << fn
    }
    pnmstat_path = File.dirname(File.dirname(File.dirname(__FILE__)))+'/bin/pnmstat'
    command = [pnmstat_path, *fs.map {|f| f.to_s }]
    json = IO.popen(command) {|f| f.read }
    h = JSON.load(json)
    h2 = {}
    h.each {|k,v|
      v['page'] = pages[k]
      h2[File.basename(k)] = v
    }
    partfile(js_fn) {|tmp_fn|
      File.open(tmp_fn, 'w') {|f|
        f.puts JSON.pretty_generate(h2)
      }
    }
    file_stat(js_fn)
  }

  rule(%r{#{PDIR}all\z}) {|match, all_fn|
    dir = Pathname.new(match[:dir])
    stems = image_stem_list(dir)
    size = 'small'
    %w[c g m].each {|color|
      stems.each {|stem|
        make("#{dir}.bookbox/#{size}#{stem}_#{color}.png")
      }
    }
    make("#{dir}.bookbox/stat.js")
  }

  rule(%r{#{PDIR}all-full\z}) {|match, all_fn|
    dir = Pathname.new(match[:dir])
    stems = image_stem_list(dir)
    %w[small fullsize].each {|size|
      %w[c g m].each {|color|
        stems.each {|stem|
          make("#{dir}.bookbox/#{size}#{stem}_#{color}.png")
        }
      }
    }
    make("#{dir}.bookbox/stat.js")
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
