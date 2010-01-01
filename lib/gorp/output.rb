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
        $x.text! <<-'EOF'.unindent(2)
          body {background-color: #F5F5DC}
          #banner {margin-top: 0}
          pre {font-weight: bold; margin: 0; padding: 0}
          pre.stdin {color: #800080; margin-top: 1em; padding: 0}
          pre.irb {color: #800080; padding: 0}
          pre.stdout {color: #000; padding: 0}
          pre.logger {color: #088; padding: 0}
          pre.hilight {color: #000; background-color: #FF0; padding: 0}
          pre.stderr {color: #F00; padding: 0}
          div.body {border-style: solid; border-color: #800080; padding: 0.5em}
          .issue, .traceback {background:#FDD; border: 4px solid #F00; 
                      font-weight: bold; margin-top: 1em; padding: 0.5em}
          div.body, .issue, .traceback {
            -webkit-border-radius: 0.7em; -moz-border-radius: 0.7em;}
          ul.toc {list-style: none}
          ul a {text-decoration: none}
          ul a:hover {text-decoration: underline; color: #000;
                      background-color: #F5F5DC}
          a.toc h2 {background-color: #981A21; color:#FFF; padding: 6px}
          ul a:visited {color: #000}
          h2 {clear: both}
          p.desc {font-style: italic}
          p.overview {border-width: 2px; border-color: #000;
            border-style: solid; border-radius: 4em;
            background-color: #CCF; margin: 1.5em 1.5em; padding: 1em 2em; 
            -webkit-border-radius: 4em; -moz-border-radius: 4em;}
        EOF
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
      $x.pre Time.now.httpdate, :class=>'stdout'

      cmd "#{$ruby} -v"
      cmd 'gem -v'
      cmd 'gem list'
      cmd 'echo $RUBYLIB | sed "s/:/\n/g"'

      cmd Gorp.which_rails($rails) + ' -v'
  
      if $rails != 'rails'
        Dir.chdir($rails) do
          log :cmd, 'git log -1'
          $x.pre 'git log -1', :class=>'stdin'
          `git log -1`.strip.split(/\n/).each do |line|
            line.sub! /commit (\w{40})/,
              'commit <a href="http://github.com/rails/rails/commit/\1">\1</a>'
            if $1
              $x.pre(:class=>'stdout') {$x << line.chomp}
            else
              $x.pre line.chomp, :class=>'stdout'
            end
          end
        end
      end

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
