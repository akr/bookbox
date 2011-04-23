#!/usr/bin/env ruby

# usage: images2pdf [-o output.pdf] file|dir...

require 'optparse'
require 'tmpdir'
require 'find'

def err(mesg)
  STDERR.puts mesg
  exit false
end

$opt_o = nil
$opt_verbose = false
$opt_viewerprefiernces_direction = nil
def op_images2pdf
  op = OptionParser.new
  op.def_option('-o OUTPUTFILE', '--output OUTPUTFILE', 'output PDF file') {|arg| $opt_o = arg }
  op.def_option('--verbose', 'verbose mode') { $opt_verbose = true }
  op
end

def main_images2pdf(argv)
  op = op_images2pdf
  op.parse!(argv)

  if !$opt_o && STDOUT.tty?
    err "output to terminal"
  end
  out = $opt_o || '-'

  Dir.mktmpdir('images2pdf') {|d|
    fs = []
    Find.find(*argv) {|path|
      if File.directory?(path)
        if File.file?("#{path}/scan.json") ||
           File.file?("#{path}/params.json")
          im = BookBox::ImageMaker.new
          im.verbose = true
          dir = File.realpath(path)
          dir_path = Pathname.new(dir)
          params_json_path = dir_path + "params.json"
          params = {}
          params.update im.read_scan_json(dir_path)
          params.update im.read_json(params_json_path) if params_json_path.file?
          h = hashtree_nested(params)
          h2 = h["pages"]
          h2.keys.sort_by {|f| strnumsortkey(f) }.each {|out_fn|
            colormode = h2[out_fn]["colormode"] || 'c'
            next if colormode == 'n'
            fullsize_fn = out_fn.sub(/\Aout(-*[0-9]+)\.pnm\z/,
                                     ".bookbox/fullsize\\1_#{colormode}.pnm")
            fn = "#{dir}/#{fullsize_fn}"
            im.make(fn)
            fs << fn
          }
          if params["ViewerPreferencesDirection"] &&
             $opt_viewerprefiernces_direction == nil
            $opt_viewerprefiernces_direction = params["ViewerPreferencesDirection"]
          end
          Find.prune
        end
      end
      next unless File.file? path
      fs << path
    }
    fs = fs.sort_by {|f| strnumsortkey(f) }
    pdfs = []
    num_generated = 0
    fs.each {|f|
      case f
      when %r{(\A|/)\.dep-[^/]*\.marshal\z}
        next
      when /\.pdf\z/i
        STDERR.puts "use #{f.inspect} as is." if $opt_verbose
        pdfs << f
      when /\.(tiff?)\z/i
        STDERR.puts "convert #{f.inspect} to pdf." if $opt_verbose
        n = num_generated
        num_generated += 1
        tf = "#{d}/t#{n}.pnm"
        ef = "#{d}/t#{n}.err"
        of = "#{d}/t#{n}.pdf"
        system("tifftopnm --headerdump #{f} > #{tf} 2> #{ef}") # xxx
        info = File.read(ef)
        sam2p_dpi = 72
        dpi = 72
        #if %r{Resolution: (\d+), (\d+) pixels/inch} =~ info
        #  dpi = $1.to_i
        #  # sam2p 0.47 generates bigger image for bigger resolution... sigh.
        #  sam2p_dpi = 72 * (72.0 / dpi)
        #end
        #system("sam2p", "-j:quiet", "-pdf:2", "-m:dpi:#{sam2p_dpi}", tf, of)
        system("convert", "-density", dpi.to_s, f, of)
        pdfs << of
      when /\.(pnm|pbm|pgm|ppm|xpm|gif|lbm|tga|pcx|jpe?g|png|ps|eps)\z/i
        STDERR.puts "convert #{f.inspect} to pdf." if $opt_verbose
        n = num_generated
        num_generated += 1
        of = "#{d}/t#{n}.pdf"
        #system("sam2p", "-j:quiet", "-pdf:2", f, of)
        #system("convert", f, of)
        #system("convert", "-compress", "LZW", f, of)
        #system("convert", "-compress", "Zip", '-quality', '1', f, of)
        system("convert", "-compress", "Zip", f, of)
        pdfs << of
      else
        warn "unexpected file type: #{f.inspect}"
      end
    }
    STDERR.puts "generate result pdf: #{out.inspect}" if $opt_verbose
    commandline = ["pdftk"]
    commandline.concat pdfs
    commandline << "cat" << "output" << out
    system(*commandline)
    if $opt_viewerprefiernces_direction == 'R2L'
      tmp_pdf = "#{d}/r2l.pdf"
      open(tmp_pdf, 'w') {|f|
        File.foreach(out) {|line|
          if line == "/Type /Catalog\n"
            f.print "/PageLayout/TwoPageRight\n"
            f.print "/ViewerPreferences<</Direction/R2L>>\n"
          end
          f.print line
        }
      }
      system('pdftk', tmp_pdf, 'output', out)
    end
  }
end
