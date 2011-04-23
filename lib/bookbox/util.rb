def strnumsortkey(s)
  a = []
  s.scan(/(\d+)|\D+/) {
    if $1
      a << 1 << $&.to_i
    else
      a << 2 << $&
    end
  }
  a
end

def partfile(filename)
  partfilename = filename.to_s + ".part"
  res = yield partfilename
  File.rename partfilename, filename
  res
end

def hashtree_flatten(h, prefix='', result={})
  h.each {|k, v|
    k2 = prefix.empty? ? k : prefix+':'+k
    if Hash === v
      hashtree_flatten(v, k2, result)
    else
      result[k2] = v
    end
  }
  result
end

def hashtree_nested(h)
  result = {}
  h.each {|k, v|
    ks = k.scan(%r{[^:]+})
    hh = result
    lastk = ks.pop
    ks.each {|s|
      hh = (hh[s] ||= {})
    }
    hh[lastk] = v
  }
  result
end

def bookbox_command
  File.join(File.dirname(File.dirname(File.dirname(__FILE__))), 'bin/bookbox')
end
