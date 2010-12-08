require 'fileutils'
require 'pathname'

unless RUBY_PLATFORM =~ /mingw32/
  require 'open3'
  FILE_SEPARATOR = '/'
  DEV_NULL = '/dev/null'
else
  require 'win32/open3'
  FILE_SEPARATOR = '\\'
  DEV_NULL = 'NUL'
end

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

# deduce environment based on provided Gemfile
unless ENV['GORP_RAILS']
  gemfile = "#{$BASE}/Gemfile" if File.exist? "#{$BASE}/Gemfile"
  gemfile = "#{$WORK}/Gemfile" if File.exist? "#{$WORK}/Gemfile"
  if gemfile
    open(gemfile) do |file|
      pattern = /^gem\s+['"](\w+)['"],\s*:path\s*=>\s*['"](.*?)['"]/
      file.read.scan(pattern).each do |name,path|
        if name == 'rails'
          ENV['GORP_RAILS'] ||= path
        else
          $: << "#{path}/lib"
        end
      end
    end
  end
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
      if $bundle
        cmd 'bundle show'
      else
        cmd 'gem list'
        cmd 'echo $RUBYLIB | sed "s/:/\n/g"'
      end
    end

    if File.exist? 'Gemfile'
      rake 'about'
    elsif File.exist? 'script/rails'
      cmd 'ruby script/rails application -v'
    else
      cmd Gorp.which_rails($rails) + ' -v'
    end
 
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
  rescue
  end

  def self.log type, message
    type = type.to_s.ljust(5).upcase
    $stdout.puts Time.now.strftime("[%Y-%m-%d %H:%M:%S] #{type} #{message}")
    $stdout.flush
  end

  def self.path *segments
    Pathname.new($WORK).join(*segments).relative_path_from(Pathname.new($BASE))
  end
end
