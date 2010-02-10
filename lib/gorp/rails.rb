require 'fileutils'
require 'open3'
require 'builder'
require 'stringio'
require 'time'

# verify that port is available for testing
if (Net::HTTP.get_response('localhost','/',$PORT).code == '200' rescue false)
  STDERR.puts "local server already running on port #{$PORT}"
  exit
end

# select a version of Rails
if ARGV.first =~ /^_\d[.\d]*_$/
  $rails = "rails #{ARGV.first}"
elsif File.directory?(ARGV.first.to_s.split(File::PATH_SEPARATOR).first.to_s)
  if ARGV.first.include?(File::PATH_SEPARATOR)
    # first path is Rails, additional paths are added to the RUBYLIBS
    libs = ENV['RUBYLIBS'].to_s.split(File::PATH_SEPARATOR)
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
    ENV['RUBYLIBS'] = libs.join(File::PATH_SEPARATOR)
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
  `#{$rails} -v 2>/dev/null`
else
  `ruby #{$rails}/railties/bin/rails -v 2>/dev/null`
end

if $?.success?
  # setup vendored environment
  FileUtils.rm_f File.join($WORK, 'vendor', 'rails')
  if $rails =~ /^rails( |$)/
    FileUtils.rm_f File.join($WORK, '.bundle', 'environment.rb')
  else
    FileUtils.mkdir_p File.join($WORK, 'vendor')
    FileUtils.ln_s $rails, File.join($WORK, 'vendor', 'rails')
    FileUtils.mkdir_p File.join($WORK, '.bundle')
    FileUtils.cp File.join(File.dirname(__FILE__), 'rails.env'),
      File.join($WORK, '.bundle', 'environment.rb')
  end
else
  puts "Install rails or specify path to git clone of rails as the " + 
    "first argument."
  Process.exit!
end

# http://redmine.ruby-lang.org/issues/show/2717
$bundle = (ENV['BUNDLE_PATH'] and (RUBY_VERSION =~ /^1\.8/))
$bundle = true  if ARGV.include?('--bundle')
$bundle = false if ARGV.include?('--vendor')

module Gorp
  # determine which version of rails is running
  def self.which_rails rails
    railties = File.join(rails, 'railties', 'bin', 'rails')
    rails = railties if File.exists?(railties)
    if File.exists?(rails)
      firstline = open(rails) {|file| file.readlines.first}
      rails = 'ruby ' + rails unless firstline =~ /^#!/
    end
    rails
  end

  module Commands
    # run rails as a command
    def rails name, app=nil
      Dir.chdir($WORK)
      FileUtils.rm_rf name
      log :rails, name

      # determine how to invoke rails
      rails = Gorp.which_rails($rails)
      rails.sub! 'ruby ', 'ruby -rubygems '

      opt = (ARGV.include?('--dev') ? ' --dev' : '')
      $x.pre "#{rails} #{name}#{opt}", :class=>'stdin'
      popen3 "#{rails} #{name}#{opt}"

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
          if $bundle
            gemfile=open('Gemfile') {|file| file.read}
            gemfile[/gem 'rails',()/,1] = " :path => #{$rails.inspect} #"
            gemfile[/^()source/, 1] = '# '
            open('Gemfile','w') {|file| file.write gemfile}
            cmd "bundle install"
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

      $rails_app = name
    end

    # stop a server if it is currently running
    def self.stop_server(restart=false)
      if !restart and $cleanup
        $cleanup.call
        $cleanup = nil
      end

      if $server
        Process.kill "INT", $server
        Process.wait($server)
        $server = nil
      end
    end

    # start/restart a rails server in a separate process
    def restart_server
      if $server
        log :server, 'restart'
	$x.h3 'Restart the server.'
        Gorp::Commands.stop_server(true)
      else
        log :CMD, 'ruby script/server'
	$x.h3 'Start the server.'
      end

      $server = fork
      if $server
	# wait for server to start
	60.times do
	  sleep 0.5
	  begin
	    status = Net::HTTP.get_response('localhost','/',$PORT).code
	    break if %(200 404).include? status
	  rescue Errno::ECONNREFUSED
	  end
	end
      else
	#
	# For unknown reason, when run as CGI, the below produces:
	#   undefined method `chomp' for nil:NilClass (NoMethodError)
	#   from rails/actionpack/lib/action_dispatch/middleware/static.rb:13
	#     path   = env['PATH_INFO'].chomp('/')
	#
	unless ENV['GATEWAY_INTERFACE'].to_s =~ /CGI/
	  STDOUT.reopen '/dev/null', 'a'
          if File.exist? 'script/rails'
	    exec "#{$ruby} script/rails server --port #{$PORT}"
          else
	    exec "#{$ruby} script/server --port #{$PORT}"
          end
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
  end
end
