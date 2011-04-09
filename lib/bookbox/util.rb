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
  partfilename = filename + ".part"
  res = yield partfilename
  File.rename partfilename, filename
  res
end
