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

  # Sony Reader

  rule(%r{/\.bookbox/sr#{PSTEM}\.pnm\z}, '/.bookbox/fullsize\k<stem>_g.pnm') {|match, dst_fn, (src_fn, src_att)|
    stem = match[:stem]
    dir = Pathname(match.pre_match)
    # 584x754
    params_json_path = dir+"params.json"
    params = file_stat(params_json_path) ? read_json(params_json_path) : {}
    colormode = params["pages:out#{stem}.pnm:colormode"]
    case colormode
    when 'm'
      run_pipeline src_fn, dst_fn,
        %w[pnmscale -xysize 584 754],
        %w[pnmnorm -bvalue 50 -wvalue 170],
        %w[pnmgamma -ungamma 2],
        %w[pnmdepth 15]
    else
      run_pipeline src_fn, dst_fn,
        %w[pnmscale -xysize 584 754],
        %w[pnmdepth 15]
    end
    dst_att = src_att.dup
    if src_att.include?("dpi")
      src_dpi = src_att["dpi"]
      src_magic, src_w, src_h = PNM.read_header(src_fn)
      dst_magic, dst_w, dst_h = PNM.read_header(dst_fn)
      dst_dpi = (src_dpi.to_f / src_w * dst_w).round
      dst_att["dpi"] = dst_dpi
    end
    dst_att
  }

  rule(%r{/\.bookbox/sr#{PSTEM}\.pdf\z}, '/.bookbox/sr\k<stem>.pnm') {|match, dst_fn, (src_fn, src_att)|
    dpi_args = []
    dpi_args = ["-density", src_att["dpi"].to_s] if src_att["dpi"]
    compress_args = %w[-compress Zip]
    partfile(dst_fn.to_s) {|tmp_fn|
      commandline = ["convert", *dpi_args, *compress_args, src_fn.to_s, "pdf:#{tmp_fn}"]
      if !system(*commandline)
        raise ArgumentError, "command failed: #{commandline.join(' ')}"
      end
    }
    src_att
  }

  rule(%r{/\.bookbox/sr\.pdf\z}) {|match, dst_fn|
    dir = Pathname(match.pre_match)
    stems = image_stem_list(dir)
    params = file_stat(dir+"params.json") ? read_json(dir+"params.json") : {}
    src_pdfs = []
    stems.each {|stem|
      if params["pages:out#{stem}.pnm:colormode"] != 'n'
        fn = dir+".bookbox/sr#{stem}.pdf"
        make(fn)
        src_pdfs << fn
      end
    }
    tmp1_fn = "#{dst_fn}.tmp1.pdf"
    tmp2_fn = "#{dst_fn}.tmp2.pdf"
    begin
      commandline = ["pdftk", *src_pdfs.map {|fn| fn.to_s }, "cat", "output", tmp1_fn]
      if !system(*commandline)
        raise ArgumentError, "command failed: #{commandline.join(' ')}"
      end
      open(tmp2_fn, 'w') {|f|
        File.foreach(tmp1_fn) {|line|
          if line == "/Type /Catalog\n"
            f.print "/PageLayout/TwoPageRight\n"
            f.print "/ViewerPreferences<</Direction/R2L>>\n"
          end
          f.print line
        }
      }
      commandline = ['pdftk', tmp2_fn, 'output', dst_fn.to_s]
      if !system(*commandline)
        raise ArgumentError, "command failed: #{commandline.join(' ')}"
      end
    ensure
      File.delete tmp1_fn if File.exist? tmp1_fn
      File.delete tmp2_fn if File.exist? tmp2_fn
    end
    nil
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
