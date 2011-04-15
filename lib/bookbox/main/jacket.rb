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
  if sizes.map {|fn, w, h| w }.uniq.length == 1 &&
     sizes.map {|fn, w, h| h }.uniq.length != 1
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

  rotate,
  jacket_fn, jacket_w,
  cover_fn, cover_w,
  content_fn, content_w = find_pages(filenames)
  #p find_pages(filenames)

  front_jacket_x = (jacket_w - cover_w) / 2
  front_jacket_w = cover_w - content_w
  back_jacket_x = front_jacket_x + content_w

  front_jacket_x -= front_jacket_w * 0.05
  back_jacket_x -= front_jacket_w * 0.05
  front_jacket_w += front_jacket_w * 0.05
  front_jacket_x = front_jacket_x.round
  back_jacket_x = back_jacket_x.round
  front_jacket_w = front_jacket_w.round
  front_jacket_x = 0 if front_jacket_x < 0
  back_jacket_x = 0 if back_jacket_x < 0

  command1 = mkcommand(rotate, front_jacket_x, front_jacket_w, jacket_fn)
  command2 = mkcommand(rotate, back_jacket_x, front_jacket_w, jacket_fn)

  front_jacket_fn = jacket_fn.sub(/\d+/) { "%0#{$&.length}d" % 0 }
  system(*command1, :out => front_jacket_fn)
  back_jacket_fn = jacket_fn.sub(/\d+/) { "%0#{$&.length}d" % 1 }
  system(*command2, :out => back_jacket_fn)

  if File.file?("scan.json")
    params = File.open("scan.json") {|f| JSON.load(f) }
    params2 = {}
    pat = /\Apages:(#{Regexp.escape jacket_fn}):/
    params.each {|k, v|
      next if pat !~ k
      params2["pages:#{front_jacket_fn}:#{$'}"] = v
      params2["pages:#{back_jacket_fn}:#{$'}"] = v
    }
    File.open("scan2.json", 'w') {|f| f.puts JSON.pretty_generate(params2) }
  end
end
