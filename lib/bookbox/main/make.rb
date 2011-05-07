require 'optparse'

$opt_verbose = 0
$opt_suffix = ''

def op_make
  op = OptionParser.new
  op.banner = 'Usage: bookbox make target...'
  op.def_option('-h', '--help', 'show help message') { puts op; exit 0 }
  op.def_option('--verbose', 'verbose mode') { $opt_verbose += 1 }
  op.def_option('-s SUFFIX', '--suffix=SUFFIX', 'specify suffix') {|arg| $opt_suffix = arg }
  op
end

def main_make(argv)
  op_make.parse!(argv)
  im = BookBox::ImageMaker.new
  im.verbose = $opt_verbose
  argv.each {|arg|
    arg += $opt_suffix
    # File.realpath and File.realdirpath is not usable because directories may not be exist.
    pp im.make File.expand_path(arg)
  }
end
