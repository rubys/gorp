require 'fileutils'
require 'time'

at_exit do
  next unless $output
  RUNFILE = File.join($WORK, 'status.run')
  open(RUNFILE,'w') {|running| running.puts(Process.pid)}
  at_exit { FileUtils.rm_f RUNFILE }

  $x.declare! :DOCTYPE, :html
  $x.html :xmlns => 'http://www.w3.org/1999/xhtml' do
    $x.head do
      $x.title $title
      $x.meta 'charset'=>'utf-8'
      $x.style :type => "text/css" do
        open(File.join(File.dirname(__FILE__), 'output.css')) do |file|
          $x.text! file.read.gsub(/^/, '      ')
        end
      end
    end
 
    $x.body class: 'awdwr' do
      $x.h1 $title, :id=>'banner'
      $x.h2 'Table of Contents'
      $x.ul :class => 'toc'
  
      # determine which range(s) of steps are to be executed
      ranges = ARGV.grep(/^ \d+(.\d+)? ( (-|\.\.) \d+(.\d+)? )? /x).map do |arg|
        bounds = arg.split(/-|\.\./)
        Range.new(secsplit(bounds.first), secsplit(bounds.last))
      end
  
      # optionally capture screenshots
      if ARGV.delete('-i') or ARGV.delete('--images')
        ENV['GORP_SCREENSHOTS'] = 'true'
      end

      # optionally save a snapshot
      if ARGV.include?('restore') or ARGV.include?('--restore')
        log :snap, 'restore'
        Dir.chdir $BASE
        FileUtils.rm_rf $WORK
        FileUtils.mkdir_p $WORK
        FileUtils.cp_r Dir["snapshot" + '/*'], $WORK
        Dir.chdir $WORK
        if $autorestart and File.directory? $autorestart
          Dir.chdir $autorestart
          restart_server
        end
        ENV.keys.dup.each {|key| ENV.delete(key) if key =~ /^BUNDLER?_/}
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
            section_head section, title
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
          # terminate server
          Gorp::Commands.stop_server
 
          # optionally save a snapshot
          if ARGV.include?('save') or ARGV.include? '--save'
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
  Gorp.log :WRITE, Gorp.path("#{$output}.html")
  open("#{$WORK}/#{$output}.html",'w') { |file| file.write $x.target! }
  
  # run tests
  if $checker
    Gorp.log :CHECK, "#{$output}.html"
    Dir.chdir $WORK
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
