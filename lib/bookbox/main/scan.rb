#!/usr/bin/env ruby

# usage:
#
# 1. set bunko as landscape
# 2. run scan-bunko

# set the first page (front face) bottom 
# landscape

require 'optparse'
require 'json'
require 'open3'

$opt_d = '.'
$opt_s = nil
$opt_f = nil
$opt_w = 215.872

def op_scan
  op = OptionParser.new
  op.def_option('-h', '--help', 'show help message') { puts op; exit 0 }
  op.def_option('-d DIR', '--destination-directory DIR', 'destination directory') {|arg| $opt_d = arg }
  op.def_option('-s START', '--start-page START', 'start page number') {|arg| $opt_s = arg }
  op.def_option('-f', '--force-scan', 'disable double feed detection') { $opt_f = true }
  op.def_option('-w WIDTH', '--scan-width WIDTH', 'specify scan width') {|arg| $opt_w = parse_length(arg) }
  op
end

def parse_length(arg)
  if /\A(\d+(?:\.\d+)?)(cm|mm)\z/ =~ arg
    n = $1.to_f
    u = $2
    case u
    when 'cm'
      n *= 10
    when 'mm'
    else
      raise ArgumentError, "unexpected unit: #{unit}"
    end
  else
    raise ArgumentError, "invalid length: #{arg}"
  end
  n
end

def main_scan(argv)
  op = op_scan
  op.parse(argv)

  width = $opt_w

  outdir = $opt_d
  unless File.directory? outdir
    Dir.mkdir outdir
  end

  if $opt_s
    start = $opt_s.to_i
    pagenum_width = $opt_s.length
  else
    nums = Dir.entries(outdir).reject {|f|
      /\Aout([0-9]+)\.pnm\z/ !~ f
    }.map {|f| f[/\d+/].to_i }
    if nums.empty?
      start = 1000
    else
      start = nums.max + 1
    end
    pagenum_width = 4
  end

  max_width = 215.872
  top_left_x = (max_width-width)/2
  resolution_dpi = 300 # dot per inch

  if $opt_f
    df_options = %w[
      --df-action=Default
    ]
  else
    df_options = %w[
      --df-action=Stop
      --df-skew
      --df-thickness
      --df-length
    ]
  end
  command = [
    "scanimage",
    "--batch=#{outdir}/out%0#{pagenum_width}d.pnm",
    "--batch-start=#{start}",
    "--source", "ADF Duplex",
    "--mode", "Color",
    "--resolution", resolution_dpi.to_s,
    "-l", top_left_x.to_s,
    "-x", width.to_s,
    "-y", "876.695",
    "--page-height", "876.695",
    "--ald=yes",
    #"--swcrop=yes",
    *df_options
  ]
  p command
  system(*command)

  scan_json_path = "#{outdir}/scan.json"
  if File.exist? scan_json_path
    scan_params = File.open(scan_json_path) {|f| JSON.load(f) }
  else
    scan_params = {}
  end

  fs = Dir.entries(outdir).reject {|f| /\Aout([0-9]+)\.pnm\z/ !~ f }
  fs = fs.sort_by {|f| f[/\d+/].to_i }

  scan_params["ViewerPreferencesDirection"] = 'R2L'

  fs.each {|f|
    n = f[/\d+/].to_i
    next if n < start
    scan_params["pages:#{f}:dpi"] = resolution_dpi
    scan_params["pages:#{f}:rotate"] = (n-start) % 2 == 0 ? 90 : 270
  }

  tmp_scan_json_path = scan_json_path + '.part'
  File.open(tmp_scan_json_path, 'w') {|f|
    f.puts JSON.pretty_generate(scan_params)
  }
  File.rename tmp_scan_json_path, scan_json_path
end
