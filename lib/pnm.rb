class PNM
  WSP = /(?:[ \t\r\n]|\#[^\r\n]*[\r\n])+/

  def self.read_header(fn)
    content = File.open(fn, 'rb') {|f| f.read }
    if /\A(P[635241])#{WSP}(\d+)#{WSP}(\d+)#{WSP}(\d+)[ \t\r\n]/o !~ content
      raise ArgumentError, "unsupported format"
    end

    magic = $1
    w = $2.to_i
    h = $3.to_i
    max = $4.to_i
    hlen = $&.bytesize
    [magic, w, h, max, hlen]
  end
end

