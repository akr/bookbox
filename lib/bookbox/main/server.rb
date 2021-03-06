require 'optparse'
require 'webrick'
require 'erb'

#$opt_image_dir = '.'
$opt_docroot = File.dirname(File.dirname(File.dirname(File.dirname(File.realpath(__FILE__))))) + "/docroot"
$opt_verbose = 0

include ERB::Util

def op_server
  op = OptionParser.new
  op.banner = 'Usage: bookbox server directory...'
  op.def_option('-h', '--help', 'show help message') { puts op; exit 0 }
  op.def_option('--verbose', 'verbose mode') { $opt_verbose += 1 }
  #op.def_option('-d DIR', '--image-dir DIR', 'image directory (default: ".")') {|arg| $opt_image_dir = arg }
  op
end

module ServletUtil
  def err(req, res, mesg)
    res['content-type'] = 'text/html'
    res.body = "<title>#{h mesg}</title>#{h mesg}"
    nil
  end

  def redirect(res, uri)
    res['content-type'] = 'text/html'
    res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, uri)
    nil
  end
end

class BookBoxHandler < WEBrick::HTTPServlet::AbstractServlet
  include ServletUtil

  def initialize(server, docroot, im, dirs)
    @server = server
    @config = server.config
    @docroot = docroot
    @im = im
    @dirs = dirs
  end

  def erb_filter(erb_filename, req, res, content, params)
    content = content.gsub(/^[ \t]*%/, '%')
    erb = ERB.new(content, nil, '%')
    erb.filename = erb_filename
    erb.result(binding)
  end

  def get_params(dir)
    if File.file?("#{dir}/params.json")
      params = File.open("#{dir}/params.json") {|f| JSON.load(f) }
    else
      params = {}
    end
    scan_params = @im.read_scan_json(dir)
    params = scan_params.merge(params)
    stems = @im.image_stem_list(dir)
    params["ViewerPreferencesDirection"] ||= "L2R"
    stems.each_with_index {|stem, i|
      params["pages:out#{stem}.pnm:colormode"] ||= "g"
      params["pages:out#{stem}.pnm:page"] = i.to_s
    }
    params
  end

  def do_GET(req, res)
    #p [:BookBoxHandler, req.path]
    filename = ''
    path = req.path
    path += 'index.html' if %r{/\z} =~ path
    path.scan(%r{/([^/]*)}) {
      seg = $1
      return err(req, res, "path contains #{seg.inspect}") if seg == '.' || seg == '..'
      filename << '/' << seg
    }
    params = nil
    if %r{\A/([^/.]+)/i(/|\z)} =~ filename
      return make_get(req, res)
    elsif %r{\A/([^/.]+)(/|\z)} =~ filename
      # http://host:port/nnn/index.html => docroot/b/index.html
      dir_id = $1
      return err(req, res, "unexpected directory id: #{dir_id}") if !@dirs.include?(dir_id)
      dir = @dirs[dir_id]
      params = get_params(dir)
      filename = filename.sub(%r{\A/([^/.]+)(/|\z)}) { "/b#{$2}" }
    end
    filename = @docroot + filename
    return err(req, res, "file not found: #{filename}") unless File.file? filename
    content = File.binread(filename)
    case filename
    when /\.html\z/ then res['content-type'] = 'text/html'
    when /\.js\z/ then res['content-type'] = 'text/javascript'
    when /\.css\z/ then res['content-type'] = 'text/css'
    when /\.png\z/ then res['content-type'] = 'image/png'
    end
    if %r{\Atext/} =~ res['content-type'] && /\A%#erb/ =~ content
      content = erb_filter(filename, req, res, content, params)
    end
    res.body = content
    nil
  end

  def make_get(req, res)
    case req.path
    when '/([^/.]+)/i'
      redirect(res, "/#{$1}/i/")
    when %r{\A/([^/.]+)/i/\z}
      dir = @dirs[dir_id = $1]
      return err(req, res, "unexpected directory id: #{dir_id}") if !dir
      req.path_info = "/"
      WEBrick::HTTPServlet::FileHandler.get_instance(@server, dir, :FancyIndexing => true).service(req, res)
    when %r{\A/([^/.]+)/i/([^/]+)\z}
      dir_id = $1
      basename = $2
      dir = @dirs[dir_id]
      return err(req, res, "unexpected directory id: #{dir_id}") if !dir
      #return redirect(res, "file://#{dir}/.bookbox/#{basename}")
      res.filename = "#{dir}/.bookbox/#{basename}"
      @im.make(res.filename)
      WEBrick::HTTPServlet::DefaultFileHandler.get_instance(@config, res.filename).service(req, res)
    else
      err(req, res, "unexpected uri: #{req.request_uri}")
    end
    nil
  end

  def do_POST(req, res)
    case req.path
    when %r{\A/([^/.]+)/submit\z}
      dir_id = $1
      return err(req, res, "unexpected directory id: #{dir_id}") if !@dirs.include?(dir_id)
      save(@dirs[dir_id], req.query)
      redirect(res, "/#{$1}/")
    else
      err(req, res, "unexpected uri: #{req.request_uri}")
    end
    nil
  end

  def save(dir, query)
    stems = @im.image_stem_list(dir)
    stem_hash = {}
    stems.each {|stem| stem_hash[stem] = stem }
    params = {}
    query.each {|k,v|
      case k
      when 'ViewerPreferencesDirection'
        next if !%w[L2R R2L].include?(v)
        params[k] = v
      when /\Apages:out(-*[0-9]+)\.pnm:(dpi|rotate|colormode|page)\z/
        stem_maybe = $1
        attr_key = $2
        next if !stem_hash[stem_maybe]
        stem = stem_maybe
        case attr_key
        when 'dpi'
          next if /\d+/ !~ v
          v = v.to_i
        when 'rotate'
          next if /0|90|180|270/ !~ v
          v = v.to_i
        when 'colormode'
          next if !%w[c g m n].include?(v)
        end
        name = "pages:out#{stem}\.pnm:#{attr_key}"
        params[name] = v
      end
    }
    scan_params = @im.read_scan_json(dir)
    scan_params.each {|k,v|
      params.delete(k) if params[k] == v
    }
    partfile("#{dir}/params.json") {|fn|
      File.open(fn, "w") {|f|
        f.puts JSON.pretty_generate(params)
      }
    }
  end
end

def main_server(argv)
  op_server.parse!(argv)
  dirs = {}
  argv.each_with_index {|dir, i|
    dir = Pathname.new(File.realpath(dir))
    basename = dir.basename.to_s.gsub(/\./, '_')
    if dirs.include?(basename)
      warn "ambiguous directory filename: #{basename.inspect}"
      next
    end
    dirs[basename] = dir
  }
  im = BookBox::ImageMaker.new
  im.verbose = $opt_verbose
  webrick_config = {
    :DocumentRoot => '/home/username/public_html/',
    :BindAddress => '127.0.0.1',
    :Port => 10080}
  srv = WEBrick::HTTPServer.new(webrick_config)
  url = "http://#{srv[:BindAddress]}:#{srv[:Port]}"
  srv.logger.info url
  trap("INT"){ srv.shutdown }
  trap("TERM"){ srv.shutdown }
  trap("QUIT"){ srv.shutdown }
  srv.mount('', BookBoxHandler, $opt_docroot, im, dirs)
  srv.start
end
