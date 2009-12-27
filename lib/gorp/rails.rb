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
elsif File.directory?(ARGV.first.to_s)
  $rails = ARGV.first
  $rails = File.join($rails,'rails') if
    File.directory?(File.join($rails,'rails'))
  $rails = File.expand_path($rails)
else
  $rails = 'rails'
end

# determine which version of rails is running
def which_rails rails
  railties = File.join(rails, 'railties', 'bin', 'rails')
  rails = railties if File.exists?(railties)
  if File.exists?(rails)
    firstline = open(rails) {|file| file.readlines.first}
    rails = 'ruby ' + rails unless firstline =~ /^#!/
  end
  rails
end

# run rails as a command
def rails name, app=nil
  Dir.chdir($WORK)
  FileUtils.rm_rf name
  log :rails, name

  # determine how to invoke rails
  rails = which_rails $rails

  $x.pre "#{rails} #{name}", :class=>'stdin'
  popen3 "#{rails} #{name}"

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

  cmd 'rake rails:freeze:edge' if ARGV.include? 'edge'

  if $rails != 'rails' and File.directory?($rails)
    cmd "mkdir vendor" unless File.exist?('vendor')
    cmd "ln -s #{$rails} vendor/rails"
  end
end

# start/restart a rails server in a separate process
def restart_server
  log :server, 'restart'
  if $server
    $x.h3 'Restart the server.'
    Process.kill "INT", $server
    Process.wait($server)
  else
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
    STDOUT.reopen '/dev/null', 'a'
    exec "#{$ruby} script/server --port #{$PORT}"

    # alternatives to the above, with backtrace
    begin
      if File.exist?('config.ru')
        require 'rack'
        server = Rack::Builder.new {eval(open('config.ru') {|file| file.read})}
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
