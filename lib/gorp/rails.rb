require 'fileutils'
require 'builder'
require 'stringio'
require 'time'

module Gorp
  # determine which version of rails is running
  def self.which_rails rails
    railties = File.join(rails, 'railties', 'exe', 'rails')
    rails = railties if File.exist?(railties)

    railties = File.join(rails, 'railties', 'bin', 'rails')
    rails = railties if File.exist?(railties)

    bin = File.join(rails, 'bin', 'rails')
    rails = bin if File.exist?(bin)

    if File.exist?(rails)
      firstline = open(rails) {|file| file.readlines.first}
      rails = 'ruby ' + rails unless firstline =~ /^#!/
    end
    rails
  end
end

# verify that port is available for testing
if (Net::HTTP.get_response('0.0.0.0','/',$PORT).code == '200' rescue false)
  STDERR.puts "local server already running on port #{$PORT}"
  exit
else
  Dir['*/tmp/*/pids/*.pid'].each do |pidfile|
    File.unlink pidfile
  end

  `lsof -ti tcp:8080`.split.each do |pid|
    Process.kill 9, pid.to_i
  end
end

# select a version of Rails
if ARGV.first =~ /^_\d[.\d]*_$/
  $rails = "rails #{ARGV.first}"
elsif File.directory?(ARGV.first.to_s.split(File::PATH_SEPARATOR).first.to_s)
  if ARGV.first.include?(File::PATH_SEPARATOR)
    # first path is Rails, additional paths are added to the RUBYLIB
    libs = ENV['RUBYLIB'].to_s.split(File::PATH_SEPARATOR)
    ARGV.first.split(File::PATH_SEPARATOR).reverse.each do |lib|
      lib = File.expand_path(lib)
      if !File.directory?(lib)
        STDERR.puts "No such library: #{lib.inspect}"
        exit
      elsif File.directory?(File.join(lib,'lib'))
        libs.unshift File.join(lib,'lib')
      else
        libs.unshift lib
      end
    end
    $rails = libs.shift
    $:.unshift *libs
  else
    $rails = ARGV.first
  end

  if File.directory?(File.join($rails,'rails'))
    $rails = File.join($rails,'rails')
  end

  $rails = File.expand_path($rails)
else
  $rails = ENV['GORP_RAILS'] || 'rails'
end

# verify version of rails
if $rails =~ /^rails( |$)/
  `#{$rails} -v 2>#{DEV_NULL}`
else
  `#{Gorp.which_rails($rails)} -v 2>#{DEV_NULL}`
end

unless $?.success?
  puts "Install rails or specify path to git clone of rails as the " + 
    "first argument."
  Process.exit!
end

# http://redmine.ruby-lang.org/issues/show/2717
$bundle = File.exist?(File.join($rails, 'Gemfile'))
$bundle = true  if ARGV.include?('--bundle')
$bundle = false if ARGV.include?('--vendor')

if $bundle
  require 'bundler/setup'
else
  # setup vendored environment
  FileUtils.rm_f File.join($WORK, 'vendor', 'rails')
  if $rails =~ /^rails( |$)/
    FileUtils.rm_f File.join($WORK, '.bundle', 'environment.rb')
  else
    FileUtils.mkdir_p File.join($WORK, 'vendor')
    begin
      FileUtils.ln_s $rails, File.join($WORK, 'vendor', 'rails')
    rescue NotImplementedError
      FileUtils.cp_r $rails, File.join($WORK, 'vendor', 'rails')
    end
    FileUtils.mkdir_p File.join($WORK, '.bundle')
    FileUtils.cp File.join(File.dirname(__FILE__), 'rails.env'),
      File.join($WORK, '.bundle', 'environment.rb')
  end
end

module Gorp
  module Commands
    # run rails as a command
    def rails name, app=nil, opt=''
      Dir.chdir($WORK)
      FileUtils.rm_rf name
      log :rails, name
      $rails_app = name

      # determine how to invoke rails
      rails = Gorp.which_rails($rails)
      rails += ' new' if `#{rails} -v` !~ /Rails 2/ 
      gemfile = ENV['BUNDLE_GEMFILE'] || 'Gemfile'
      if File.exist? gemfile
        rails = "bundle exec " + rails
        opt += ' --skip-bundle'
        unless File.read("#$rails/RAILS_VERSION") =~ /^[34]/
          opt += ' --skip-listen' 
        end
        opt += ' --dev' if File.read(gemfile) =~ /gem ['"]rails['"], :path/
      elsif `ruby -v` =~ /1\.8/
        rails.sub! /^/, 'ruby ' unless rails =~ /^ruby /
        rails.sub! 'ruby ', 'ruby -rubygems '
      end

      $x.pre "#{rails.gsub('/',FILE_SEPARATOR)} #{name}#{opt}", :class=>'stdin'
      popen3 "#{rails} #{name}#{opt.sub(' --dev','')}"

      # canonicalize the reference to Ruby
      Dir["#{name}/script/**/*"].each do |script|
        next if File.directory? script
        code = open(script) {|file| file.read}
        code.sub! /^#!.*/, '#!/usr/bin/env ruby'
        open(script,'w') {|file| file.write code}
      end

      cmd "mkdir #{name}" unless File.exist?(name)
      Dir.chdir(name)
      FileUtils.rm_rf 'public/.htaccess'

      cmd 'rake rails:freeze:edge' if ARGV.include? '--edge'

      if $rails != 'rails' and File.directory?($rails)
        if File.exist? 'Gemfile'
          gemfile=open('Gemfile') {|file| file.read}
          gemfile[/^gem ["']rails['"],()/,1] = " :path => #{$rails.inspect} #"
          ENV['RUBYLIB'].split(File::PATH_SEPARATOR).each do |path|
            path.sub! /\/lib$/, ''
            name = path.split(File::SEPARATOR).last
            next if %w(gorp rails).include? name
            next if name == 'rb-inotify' and RUBY_PLATFORM =~ /darwin/
            if File.exist?(File.join(path, "/#{name}.gemspec"))
              # replace version with path; retaining group
              # note archaic Ruby 1.8.7 hash syntax used as a marker,
              # these changes are undone by pub_gorp
              if gemfile =~ /^\s*gem ['"]#{name}['"],\s*:git/
                gemfile[/^\s*gem ['"]#{name}['"],\s*(:git\s*=>\s*).*/,1] = 
                  ":path => #{path.inspect} # "
              elsif gemfile =~ /^\s*gem ['"]#{name}['"],/
                gemfile[/^\s*gem ['"]#{name}['"],\s*()/,1] = 
                  ":path => #{path.inspect} # "
              else
                groups = gemfile.scan(/^group (.*?) do(.*?)\nend/m).
                  find {|groups, defn| defn.include? name}
                if groups
                  groups = groups.first.gsub(':', '')
                  groups = groups.split(/,\s+/) if groups.include? ','
                end
 
                gemfile.sub!(/(^\s*gem ['"]#{name}['"])/) {|line| '# ' + line}
                gemfile[/gem ['"]rails['"],.*\n()/,1] = 
                  "gem #{name.inspect}, :path => #{path.inspect}" +
                  "#{(groups ? ", group: #{groups.inspect}" : '')}\n"
              end
            end
          end

          gemfile[/^()source/, 1] = '# '
          open('Gemfile','w') {|file| file.write gemfile}

          gemfile = File.expand_path('Gemfile')
          at_exit do
            source = File.read(gemfile)
            source[/^(# )source/, 1] = ''
            open(gemfile,'w') {|file| file.write source}
          end

          if $bundle
            begin
              rubyopt, ENV['RUBYOPT'] = ENV['RUBYOPT'], nil
              bundle "install"
            ensure
              ENV['RUBYOPT'] = rubyopt
            end
          else
            cmd "ln -s #{$rails} vendor/rails"
            system "mkdir -p .bundle"
            system "cp #{__FILE__.sub(/\.rb$/,'.env')} .bundle/environment.rb"
          end
        else
          system 'mkdir -p vendor'
          system "ln -s #{$rails} vendor/rails"
        end
      end

      if ARGV.include?('--rails-debug')
        edit 'config/initializers/rails_debug.rb' do |data|
          data.all = <<-EOF.unindent(12)
            ENV['BACKTRACE'] = '1'
            Thread.abort_on_exception = true
          EOF
        end
      end
    end

    # stop a server if it is currently running
    def self.stop_server(restart=false, signal="INT")
      if !restart and $cleanup
        $cleanup.call
        $cleanup = nil
      end

      if $server
        if $server.respond_to?(:process_id)
          # Windows
          signal = 1 if signal == "INT"
          Process.kill signal, $server.process_id
          Process.waitpid($server.process_id) rescue nil
        else
          # UNIX
          require 'timeout'
          Process.kill signal, $server
          begin
             Timeout::timeout(15) do
               Process.wait $server
             end
          rescue Timeout::Error
            Process.kill 9, $server
            Process.wait $server
          end
        end
      end

      # ensure webpacker process is stopped
      `lsof -ti tcp:8080`.split.each do |pid|
        Process.kill 9, pid.to_i
      end
    ensure
      $server = nil
    end

    # start/restart a rails server in a separate process
    def restart_server(quiet=false)
      if $server
        log :server, 'restart'
        $x.h3 'Restart the server.' unless quiet
        Gorp::Commands.stop_server(true)
      else
        log :CMD, 'rails server'
        $x.h3 'Start the server.' unless quiet
      end

      if File.exist? 'Procfile'
        rails_server = "foreman start -p #{$PORT}"
      elsif File.exist? 'bin/rails'
        rails_server = "#{$ruby} bin/rails server --port #{$PORT}"
      elsif File.exist? 'script/rails'
        rails_server = "#{$ruby} script/rails server --port #{$PORT}"
      else
        rails_server = "#{$ruby} script/server --port #{$PORT}"
      end

      if RUBY_PLATFORM !~ /mingw32/
        $server = fork
      else
        require 'win32/process'
        begin
          save = STDOUT.dup
          STDOUT.reopen(File.open('NUL','w+'))
          $server = Process.create(:app_name => rails_server, :inherit => true)
          # :startup_info => {:stdout => File.open('server.log','w+')})
        ensure
          STDOUT.reopen save
        end
      end

      if $server and File.read("#$rails/RAILS_VERSION") =~ /^4\.1/
        # wait for server to start
        60.times do
          sleep 0.5
          begin
            status = Net::HTTP.get_response('0.0.0.0','/',$PORT).code
            break if %(200 404 500).include? status
          rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
          end
        end
      elsif $server
        # wait for server to start
        34.times do |i| # about 60 seconds
          sleep 0.1 * i
          begin
            status = Net::HTTP.get_response('0.0.0.0','/',$PORT).code

            if status == '500'
              12.times do |i| # about 10 seconds
                sleep 0.1 * i
                status = Net::HTTP.get_response('0.0.0.0','/',$PORT).code
                break if %(200 404).include? status
              end
            end

            break if %(200 404 500).include? status
          rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
          end
        end
        sleep 5 if File.exist? 'Procfile'
      else
        # start a new bundler context
        ENV.keys.dup.each { |key| ENV.delete key if key =~ /^BUNDLE_/ }
        ENV.delete('RUBYOPT')

        # For unknown reason, when run as CGI, the below produces:
        #   undefined method `chomp' for nil:NilClass (NoMethodError)
        #   from rails/actionpack/lib/action_dispatch/middleware/static.rb:13
        #     path   = env['PATH_INFO'].chomp('/')
        #
        unless ENV['GATEWAY_INTERFACE'].to_s =~ /CGI/
          STDOUT.reopen '/dev/null', 'a'
          exec rails_server
        end

        # alternatives to the above, with backtrace
        begin
          if File.exist?('config.ru')
            require 'rack'
            server = Rack::Builder.new {eval(open('config.ru') {|fh| fh.read})}
            Rack::Handler::WEBrick.run(server, :Port => $PORT)
          else
            ARGV.clear.unshift('--port', $PORT.to_s)

            # start server, redirecting stdout to a string
            $stdout = StringIO.open('','w')
            require './config/boot'
            if Rails::VERSION::MAJOR == 2
              require 'commands/server'
            else
              require 'rails/commands/server'
              Rails::Server.start
            end
          end
        rescue 
          STDERR.puts $!
          $!.backtrace.each {|method| STDERR.puts "\tfrom " + method}
        ensure
          Process.exit!
        end
      end
    end

    alias_method :start_server, :restart_server
  end
end
