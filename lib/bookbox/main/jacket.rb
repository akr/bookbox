require 'json'

WSP = /(?:[ \t\r\n]|\#[^\r\n]*[\r\n])+/

def find_pages(filenames)
  sizes = []
  filenames.each {|fn|
    File.open(fn, 'rb') {|f|
      head = f.read(4096)
      if /\A(P[1-6])#{WSP}(\d+)#{WSP}(\d+)#{WSP}(\d+)[ \t\r\n]/o !~ head
        warn "PNM header not found: #{fn}"
        next
      end
      w = $2.to_i
      h = $3.to_i
      sizes << [fn, w, h]
    }
  }

  rotate = false
  if true # xxx: should read scan.json.
    sizes.map! {|fn, w, h| [fn, h, w] }
    rotate = true
  end

  sorted_sizes = sizes.sort_by.with_index {|(fn, w, h), i| [w, i] }

  max_w = sorted_sizes[-1][1]
  jacket_fn, jacket_w, = sizes.reject {|fn, w, h| w < max_w*0.9 }[0]
  content_fn, content_w, = sorted_sizes[sizes.length/2]
  cover_fn, cover_w = sorted_sizes.find {|fn, w, h| content_w * 2 < w }
  return rotate, jacket_fn, jacket_w, cover_fn, cover_w, content_fn, content_w
end

def mkcommand(rotate, x, w, jacket_fn)
  if rotate
    command1 = ['pnmcut', '-top', x.to_s, '-height', w.to_s, jacket_fn]
  else
    command1 = ['pnmcut', '-left', x.to_s, '-width', w.to_s, jacket_fn]
  end
end

def main_jacket(argv)

  filenames = Dir.entries(".").reject {|fn| /\Aout-*[0-9]+\.pnm\z/ !~ fn }
  filenames = filenames.sort_by {|fn| strnumsortkey(fn) }

  if filenames[0][/\d+/].to_i == 0
    raise "title page already exist: #{filenames[0]}"
  end

  fp = find_pages(filenames)
  rotate,
  jacket_fn, jacket_w,
  cover_fn, cover_w,
  content_fn, content_w = fp

  content_w = (content_w * 1.05).round

  flap_w = (jacket_w - cover_w) / 2
  spine_w = cover_w - content_w * 2

  front_flap_x = 0
  front_flap_w = flap_w
  front_jacket_x = front_flap_x + flap_w
  front_jacket_w = content_w + spine_w
  back_jacket_x = front_jacket_x + front_jacket_w
  back_jacket_w = content_w
  back_flap_x = back_jacket_x + back_jacket_w
  back_flap_w = flap_w

  ary = []
  ary << mkcommand(rotate, front_jacket_x, front_jacket_w, jacket_fn)
  ary << mkcommand(rotate, front_flap_x, front_flap_w, jacket_fn)
  ary << mkcommand(rotate, back_flap_x, back_flap_w, jacket_fn)
  ary << mkcommand(rotate, back_jacket_x, back_jacket_w, jacket_fn)

  fmt = "%0#{$&.length}d"
  fns = []
  ary.each_with_index {|command, i|
    fn = jacket_fn.sub(/\d+/) { fmt % i }
    fns << fn
    system(*command, :out => fn)
  }

  if File.file?("scan.json")
    params = File.open("scan.json") {|f| JSON.load(f) }
    params2 = {}
    pat = /\Apages:(#{Regexp.escape jacket_fn}):/
    params.each {|k, v|
      next if pat !~ k
      fns.each {|fn|
        params2["pages:#{fn}:#{$'}"] = v
      }
    }
    File.open("scan2.json", 'w') {|f| f.puts JSON.pretty_generate(params2) }
  end
end
