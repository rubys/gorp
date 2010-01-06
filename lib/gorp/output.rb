require 'fileutils'
require 'time'

at_exit do
  next unless $output
  RUNFILE = File.join($WORK, 'status.run')
  open(RUNFILE,'w') {|running| running.puts(Process.pid)}
  at_exit { FileUtils.rm_f RUNFILE }

  $x.declare! :DOCTYPE, :html
  $x.html :xmlns => 'http://www.w3.org/1999/xhtml' do
    $x.header do
      $x.title $title
      $x.meta 'http-equiv'=>'text/html; charset=UTF-8'
      $x.style :type => "text/css" do
        open(File.join(File.dirname(__FILE__), 'output.css')) do |file|
          $x.text! file.read.gsub(/^/, '      ')
        end
      end
    end
  
    $x.body do
      $x.h1 $title, :id=>'banner'
      $x.h2 'Table of Contents'
      $x.ul :class => 'toc'
  
      # determine which range(s) of steps are to be executed
      ranges = ARGV.grep(/^ \d+(.\d+)? ( (-|\.\.) \d+(.\d+)? )? /x).map do |arg|
        bounds = arg.split(/-|\.\./)
        Range.new(secsplit(bounds.first), secsplit(bounds.last))
      end
  
      # optionally save a snapshot
      if ARGV.include? 'restore'
        log :snap, 'restore'
        Dir.chdir $BASE
        FileUtils.rm_rf $WORK
        FileUtils.cp_r "snapshot", $WORK, :preserve => true
        Dir.chdir $WORK
        if $autorestart and File.directory? $autorestart
          Dir.chdir $autorestart
          restart_server
        end
      end
  
      # run steps
      e = nil
      begin
        $sections.each do |section, title, steps|
	  omit = secinclude($omit, section)
	  omit ||= (!ranges.empty? and !secinclude(ranges, section))

	  if omit
            $x.a(:class => 'omit', :id => "section-#{section}") do
              $x.comment! title
            end
          else
	    head section, title
	    steps.call
          end
        end
      rescue Exception => e
        $x.pre :class => 'traceback' do
	  STDERR.puts e.inspect
	  $x.text! "#{e.inspect}\n"
	  e.backtrace.each {|line| $x.text! "  #{line}\n"}
        end
      ensure
        if e.class != SystemExit
	  $cleanup.call if $cleanup
  
          # terminate server
	  Process.kill "INT", $server if $server
	  Process.wait($server) if $server
  
          # optionally save a snapshot
          if ARGV.include? 'save'
            log :snap, 'save'
            Dir.chdir $BASE
            FileUtils.rm_rf "snapshot"
            FileUtils.cp_r $WORK, "snapshot", :preserve => true
          end
        end
      end

      $x.a(:class => 'toc', :id => 'env') {$x.h2 'Environment'}
      Gorp.dump_env

      $x.a(:class => 'toc', :id => 'todos') {$x.h2 'Todos'}
      $x.ul :class => 'todos'
    end
  end
  
  # output results as HTML, after inserting style and toc information
  $x.target![/<style.*?>()/,1] = "\n#{$style.target!.strip.gsub(/^/,' '*6)}\n"
  $x.target!.sub! /<ul class="toc"\/>/,
    "<ul class=\"toc\">\n#{$toc.target!.gsub(/^/,' '*6)}    </ul>"
  $x.target!.sub! /<ul class="todos"\/>/,
    "<ul class=\"todos\">\n#{$todos.target!.gsub(/^/,' '*6)}    </ul>"
  $x.target!.gsub! '<strong/>', '<strong></strong>'
  $x.target!.gsub! /(<textarea[^>]+)\/>/, '\1></textarea>'
  log :WRITE, "#{$output}.html"
  open("#{$WORK}/#{$output}.html",'w') { |file| file.write $x.target! }
  
  # run tests
  if $checker
    log :CHECK, "#{$output}.html"
    Dir.chdir $BASE
    STDOUT.puts
    if $checker.respond_to? :call
      $checker.call
    elsif $checker =~ /^[-\w]+$/
      require File.join($BASE,$checker)
    else
      require $checker
    end
  end
end
