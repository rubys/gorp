require 'fileutils'

# determine port
if ARGV.find {|arg| arg =~ /--port=(\d+)/}
  $PORT=$1.to_i
else
  $PORT=3000
end

# base directories
$BASE=File.expand_path(File.dirname(caller.last.split(':').first)) unless $BASE
$DATA = File.join($BASE,'data')
$CODE = File.join($DATA,'code')

# work directory
if (work=ARGV.find {|arg| arg =~ /--work=(.*)/})
  ARGV.delete(work)
  $WORK = File.join($BASE,$1)
else
  $WORK = File.join($BASE, ENV['GORP_WORK'] || 'work')
end

require 'rbconfig'
$ruby = File.join(Config::CONFIG["bindir"], Config::CONFIG["RUBY_INSTALL_NAME"])

FileUtils.mkdir_p $WORK

module Gorp
  def self.dump_env
    extend Commands
    $x.pre Time.now.httpdate, :class=>'stdout'

    cmd "#{$ruby} -v"
    cmd 'gem -v'
    Dir.chdir(File.join($WORK, $rails_app.to_s)) do
      system 'pwd'
      system 'ls vendor/gems/ruby/*/cache'
      caches = Dir['vendor/gems/ruby/*/cache']
      if caches.empty?
        cmd 'gem list'
        cmd 'echo $RUBYLIB | sed "s/:/\n/g"'
      else
        cmd 'gem list | grep "^bundler "'
        caches.each {|cache| cmd "ls #{cache}"}
      end
    end

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
  end
end
