require 'optparse'

$opt_verbose = false

def op_make
  op = OptionParser.new
  op.banner = 'Usage: bookbox make target...'
  op.def_option('-h', '--help', 'show help message') { puts op; exit 0 }
  op.def_option('--verbose', 'verbose mode') { $opt_verbose = true }
  op
end

def main_make(argv)
  op_make.parse!(argv)
  im = BookBox::ImageMaker.new
  im.verbose = true if $opt_verbose
  argv.each {|arg|
    # File.realpath and File.realdirpath is not usable because directories may not be exist.
    pp im.make File.expand_path(arg)
  }
end
