#!/usr/bin/env ruby

require_relative 'images2pdf'

def op_imagedir2pdf
  op = OptionParser.new
  op.def_option('--verbose', 'verbose mode') { $opt_verbose += 1 }
  op
end

def main_imagedir2pdf(argv)
  op = op_imagedir2pdf
  op.parse!(argv)

  argv.each {|arg|
    main_images2pdf([arg, '-o', "#{arg}.pdf"])
  }
end
