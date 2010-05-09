require 'fileutils'
require 'builder'
require 'time'

module Gorp
  module Commands
    # indicate that a given step should be omitted
    $omit  = []
    def omit *sections
      sections.each do |section|
        section = [section] unless section.respond_to? :include?
        $omit << Range.new(secsplit(section.first), secsplit(section.last))
      end
    end

    # Micro DSL for declaring an ordered set of book sections
    $sections = []
    def section number, title, &steps
      number = (sprintf "%f", number).sub(/0+$/,'') if number.kind_of? Float
      $sections << [number, title, steps]
    end

    $x = Builder::XmlMarkup.new(:indent => 2)
    $toc = Builder::XmlMarkup.new(:indent => 2)
    $todos = Builder::XmlMarkup.new(:indent => 2)
    $issue = 0
    $style = Builder::XmlMarkup.new(:indent => 2)

    $semaphore = Mutex.new
    class Builder::XmlMarkup
      def pre! *args
        $semaphore.synchronize { $x.pre *args }
      end
    end

    def secsplit section
      section.to_s.split('.').map {|n| n.to_i}
    end

    def secinclude ranges, section
      # was (in Ruby 1.8): range.include?(secsplit(section))
      ranges.any? do |range| 
        ss = secsplit(section)
        (range.first <=> ss) <= 0 and (range.last <=> ss) >= 0
      end
    end

    def overview message
      $x.p message.gsub(/(^|\n)\s+/, ' ').strip, :class=>'overview'
    end

    def note message
      $x.p message, :class=>'note'
    end
    alias :desc :note

    def log type, message
      Gorp.log type, message
    end

    @@section_number = 0
    def head number, title
      $section = "#{number} #{title}".strip
      number ||= (@@section_number+=1)
      log '====>', $section

      $x.a(:class => 'toc', :id => "section-#{number}") {$x.h2 $section}
      $toc.li {$toc.a $section, :href => "#section-#{number}"}
    end

    def issue text, options={}
      log :issue, text

      $issue+=1
      $x.p :class => 'issue', :id => "issue-#{$issue}" do
	$x.text! text
	if options[:ticket]
	  $x.text! ' ('
	  $x.a "ticket #{options[:ticket]}", :href=>
	    'https://rails.lighthouseapp.com/projects/8994/tickets/' + 
	    options[:ticket].to_s
	  $x.text! ')'
	end
      end
      $todos.li do
	section = $section.split(' ').first
	$todos.a "Section #{section}:", :href => "#section-#{$section}"
	$todos.a "#{text}", :href => "#issue-#{$issue}"
      end
    end

    def db statement, highlight=[]
      log :db, statement
      $x.pre "sqlite3> #{statement}", :class=>'stdin'
      cmd = "sqlite3 --line db/development.sqlite3 #{statement.inspect}"
      popen3 cmd, highlight
    end

    def ruby args
      if args == 'script/server'
        restart_server
      else
        cmd "ruby #{args}"
      end
    end

    def rake args
      cmd "rake #{args}"
    end

    def console script
      if File.exist? 'script/rails'
        console_cmd = 'script/rails console'
      else
        console_cmd = 'script/console'
      end

      open('tmp/irbrc','w') {|fh| fh.write('IRB.conf[:PROMPT_MODE]=:SIMPLE')}
      if RUBY_PLATFORM =~ /cygwin/i
        open('tmp/irbin','w') {|fh| fh.write(script.gsub('\n',"\n")+"\n")}
        cmd "IRBRC=tmp/irbrc ruby #{console_cmd} < tmp/irbin"
        FileUtils.rm_rf 'tmp/irbin'
      elsif RUBY_PLATFORM =~ /w32/
        open('tmp/irbin','w') {|fh| fh.write(script.gsub('\n',"\r\n")+"\r\n")}
        save, ENV['IRBRC']=ENV['IRBRC'], 'tmp/irbin'
        cmd "cmd /c ruby #{console_cmd} < tmp/irbin"
        ENV['IRBRC']=save
        FileUtils.rm_rf 'tmp/irbin'
      else
        cmd "echo #{script.inspect} | IRBRC=tmp/irbrc ruby #{console_cmd}"
      end
      FileUtils.rm_rf 'tmp/irbrc'
    end

    def generate *args
      if args.length == 1
        ruby "script/generate #{args.first}"
      else
        if args.last.respond_to? :keys
          args.push args.pop.map {|key,value| "#{key}:#{value}"}.join(' ')
        end
        args.map! {|arg| arg.inspect.include?('\\') ? arg.inspect : arg}
        ruby "script/generate #{args.join(' ')}"
      end
    end

    def runner *args
      ruby "script/runner #{args.join(' ')}"
    end

    def cmd args, opts={}
      if args =~ /^ruby script\/(\w+)/ and File.exist?('script/rails')
        unless File.exist? "script/#{$1}"
          args.sub! 'ruby script/performance/', 'ruby script/'
          args.sub! 'ruby script/', 'ruby script/rails '
        end
      end

      if RUBY_PLATFORM =~ /w32/
        args.gsub! '/', '\\' unless args =~ /http:/
	args.sub! /^cmd \\c/, 'cmd /c'
	args.sub! /^cp -v/, 'xcopy /i /f /y'
	args.sub! /^ls -p/, 'dir/w'
	args.sub! /^ls/, 'dir'
	args.sub! /^cat/, 'type'
      end

      as = opts[:as] || args
      as = as.sub('ruby script/rails ', 'rails ')

      log :cmd, as
      $x.pre as, :class=>'stdin'

      if args == 'rake db:migrate'
	Dir.chdir 'db/migrate' do
	  date = '20100301000000'
	  Dir['[0-9]*'].sort_by {|fn| fn=~/201003/ ? fn : 'x'+fn}.each do |file|
	    file =~ /^([0-9]*)_(.*)$/
	    FileUtils.mv file, "#{date}_#{$2}" unless $1 == date.next!
	    $x.pre "mv #{file} #{date}_#{$2}"  unless $1 == date
	  end
	end
      end
      args += ' -C' if args == 'ls -p'
      popen3 args, opts[:highlight] || []
    end

    def popen3 args, highlight=[]
      echo = ''
      if args =~ /echo\s+((["')])(.*?)\2)\s+\|\s+(.*)$/
        args = "bash -c #{$4.inspect}"
        echo = eval($1).gsub("\\n","\n")
	$x.pre! args
      end
      Open3.popen3(args) do |pin, pout, perr|
	terr = Thread.new do
          begin
	    $x.pre! perr.readline.chomp, :class=>'stderr' until perr.eof?
          rescue EOFError
          end
	end
	tin = Thread.new do
          echo.split("\n").each do |line|
	    pin.puts line
          end
	  pin.close
	end
	until pout.eof?
          begin
	    line = pout.readline
          rescue EOFError
            break
          end

	  if highlight.any? {|pattern| line.include? pattern}
	    outclass='hilight'
	  elsif line =~ /\x1b\[\d/
	    outclass = 'logger'
	    outclass = 'stderr' if line =~ /\x1b\[31m/
	    line.gsub! /(\x1b\[1m)?\x1b\[3\dm(.*?)\x1b\[0m/, '\2'
	  else
	    outclass='stdout'
	  end

	  if line.strip.size == 0
	    $x.pre! ' ', :class=>outclass
	  else
	    $x.pre! line.chomp, :class=>outclass
	  end
	end
	terr.join
        tin.join
      end
    end

    def irb file
      $x.pre "irb #{file}", :class=>'stdin'
      log :irb, file
      cmd = "irb -f -rubygems -r ./config/boot --prompt-mode simple " + 
        "#{$CODE}/#{file}"
      Open3.popen3(cmd) do |pin, pout, perr|
	terr = Thread.new do
	  until perr.eof?
	    line = perr.readline.chomp
	    line.gsub! /\x1b\[4(;\d+)*m(.*?)\x1b\[0m/, '\2'
	    line.gsub! /\x1b\[0(;\d+)*m(.*?)\x1b\[0m/, '\2'
	    line.gsub! /\x1b\[0(;\d+)*m/, ''
	    $x.pre! line, :class=>'stderr'
	  end
	end
	pin.close
	prompt = nil
	until pout.eof?
	  line = pout.readline
	  if line =~ /^([?>]>)\s*#\s*(START|END):/
	    prompt = $1
	  elsif line =~ /^([?>]>)\s+$/
	    $x.pre! ' ', :class=>'irb'
	    prompt ||= $1
	  elsif line =~ /^([?>]>)(.*)\n/
	    prompt ||= $1
	    $x.pre prompt + $2, :class=>'irb'
	    prompt = nil
	  elsif line =~ /^\w+(::\w+)*: /
	    $x.pre! line.chomp, :class=>'stderr'
	  elsif line =~ /^\s+from [\/.:].*:\d+:in `\w.*'\s*$/
	    $x.pre! line.chomp, :class=>'stderr'
	  else
	    $x.pre! line.chomp, :class=>'stdout'
	  end
	end
	terr.join
      end
    end
  end
end

# 1.8.8dev workaround for http://redmine.ruby-lang.org/issues/show/2468
x = Builder::XmlMarkup.new
x.a('b')
if x.target!.include?('*')
  class Fixnum
    def xchr(escape=true)
      n = XChar::CP1252[self] || self
      case n
      when 0x9, 0xA, 0xD, (0x20..0xD7FF), (0xE000..0xFFFD), (0x10000..0x10FFFF)
        XChar::PREDEFINED[n] or 
          (n<128 ? n.chr : (escape ? "&##{n};" : [n].pack('U*')))
      else
        '*'
      end
    end
  end
end
