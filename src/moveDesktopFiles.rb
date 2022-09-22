#!/usr/bin/env ruby
#
# movefiles

require 'yaml'
#require 'rake/pathmap'
require 'rake'
require 'pathname'
require 'syslog'
require 'fileutils'
require 'date'
require 'optparse'

@options = {}
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: moveDesktopFiles.rb [options]"
  opts.on '-d', '--dryrun', 'Dry run and do not execute'
  opts.on '-v', '--[no-]verbose', 'Make the operation more talkative'
  opts.on_tail("-h", "--help", "Show this message") do
    print opts
    exit
  end
end.parse!(into: @options)

if (@options[:verbose])
  print "options="
  p @options
end


HOMEDIR = File.expand_path('~');
TAGPATH = `brew --prefix`.chomp + "/bin/tag"
DEBUGLEVEL =  'debug' # err, warning, notice, info, debug

config = YAML.load_file("#{HOMEDIR}/.moveDesktopFiles/rules.yaml")


# puts rules.inspect
# puts ""

def dumpConfig(config)
  puts "#{config['location']}"
  config['rule_list'].each do | rl |
    puts "  #{rl['cond']}"
    rl['rules'].each do |r|
      puts "     #{r}"
    end
  end
end

def syslog(msg)
  Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.notice msg }
end

def dumpMsg(msg)
  puts msg
end

##--------------------------------------------------
# define processing rules
#
def rule_add_date(fname)
  msg = "  rule_add_date #{fname}"
  d = DateTime.now.strftime("%Y-%m-%d")
  fname = fname.pathmap("%X-#{d}%x")
  msg += "\n    fname=#{fname}"
  dumpMsg msg
  return fname
end

def rule_regex(fname, re, sb)
  msg = "  rule_regex #{fname}, #{re}, #{sb}"
  fname = fname.gsub(/#{re}/,sb)
  msg += "\n     fname=#{fname}"
  dumpMsg msg
  return fname
end

def rule_datepath(fname,pattern)
  msg = "  rule_datepath #{fname} #{pattern}"
  m = DateTime.now.strftime("%m")
  h = (((m.to_f - 1)/6) + 1).to_i
  q = (((m.to_f - 1)/3) + 1).to_i

  pattern = pattern.sub(/%H/,"H#{h}") if pattern =~ /%H/
  pattern = pattern.sub(/%Q/,"Q#{q}") if pattern =~ /%Q/
  d = DateTime.now.strftime(pattern)
  fname = "#{d}/#{fname}"
  msg += "\n    fname=#{fname}"
  dumpMsg msg
  return fname
end

##--------------------------------------------------

def doRules(rules, src)
  dst = src
  quit = false

  rules.each do | r |
    #puts "r=#{r}"
    case r
    when 'add-date'
      dst = rule_add_date(dst)
    when /regex\s*,\s*"(.*)"\s*,\s*"(.*)"/
      dst = rule_regex(dst, $1,$2)
    when /datepath\s*,\s*"(.*)"/
      dst = rule_datepath(dst, $1)
    when 'quit','quit-tag'
      quit = true
    else
      dumpMsg "unknown rule #{r}"
    end
  end

  return dst,quit
end

def doMove(src, dst)
  dst = dst.sub(/^[~\/]*/,"#{HOMEDIR}/")
  dumpMsg "     src=#{src} dst=#{dst}"
  p = Pathname.new(dst)
  if (@options[:verbose] || @options[:dryrun])
    puts "    >>dirname.mkpath #{p}"
  end
  p.dirname.mkpath() if (!@options[:dryrun])
  if (@options[:verbose] || @options[:dryrun])
    puts "    >>FileUtils.mv(#{src},#{dst})"
  end
  FileUtils.mv("#{src}","#{dst}") if (!@options[:dryrun])
end


##-----------------------------------------------------------

def doMoveFiles(folder,rules)
  folder = folder.sub(/^[~\/]*/,"#{HOMEDIR}/")
  dumpMsg "folder=#{folder}"

  #
  # Loop over all files in the folder
  #
  Dir.foreach(folder) do |src_fname|
    next if (src_fname =~/^[.~$]/)

    dst_fname = src_fname
    quit = false

    # get the Finder tags for the file
    tags = `#{TAGPATH} -N -l "#{folder}/#{src_fname}"| cut -f2`

    #puts "   src=#{src_fname} tags=#{tags}"
    # Process the rules for the file
    rules.each do | rl |
      case rl['cond']
      when /tag=(.*)$/
        this_tag = "#{$1}"
        if tags =~ /(^|,)#{$1}($|,)/
          puts "FOUND Tag match #{rl['cond']} src=#{src_fname}"
          dst_fname,quit = doRules(rl['rules'],dst_fname)

          break if quit

          if this_tag !~ /-tag$/
            # remove the tag
            if (@options[:verbose] || @options[:dryrun])
              puts "    >>tag -r #{this_tag} #{folder}/#{src_fname}"
            end
            `#{TAGPATH} -r "#{this_tag}" "#{folder}/#{src_fname}"` if (!@options[:dryrun])
          end
        end
      when 'all'
        dumpMsg "FOUND all src=#{src_fname}"
        dst_fname,quit = doRules(rl['rules'],dst_fname)
      else
        dumpMsg "unknown condition #{rl['cond']}"
      end

      break if quit

    end
    doMove("#{folder}/#{src_fname}",dst_fname) if src_fname != dst_fname
  end

end

#dumpConfig(config)

argv_str = ARGV.join(", ")
pwd = FileUtils.pwd()
syslog("moveDesktopFiles.rb called with #{argv_str} at #{pwd}")

doMoveFiles(config['location'],config['rule_list'])
