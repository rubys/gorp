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
if $EDITION
$DATA = File.join($BASE,$EDITION,'data')
else
$DATA = File.join($BASE,'data')
end
$CODE = File.join($DATA,'code')

# work directory
if (work=ARGV.find {|arg| arg =~ /--work=(.*)/})
  ARGV.delete(work)
  work = $1
else
  work = ENV['GORP_WORK'] || 'work'
end

if File.respond_to? :realpath
  $WORK = File.realpath(work, $BASE)
else
  require 'pathname'
  $WORK = Pathname.new($BASE).join(work).realpath.to_s
end

# deduce environment based on provided Gemfile
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

  Dir.chdir(File.dirname(gemfile)) do
    exit unless File.exist? 'Gemfile.lock' or system 'bundle install'
    require 'bundler/setup'
  end
end

config = RbConfig::CONFIG
$ruby = File.join(config["bindir"], config["RUBY_INSTALL_NAME"])

FileUtils.mkdir_p $WORK

module Gorp
  def self.dump_env
    extend Commands
    $x.pre Time.now.httpdate, :class=>'stdout'

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

    if File.exist? 'Gemfile'
      log :cmd, 'rake about'
      $x.pre 'rake about', :class=>'stdin'
      about = `rake about`.sub(/^(Middleware\s+)(.*)/) {
        term,dfn=$1,$2 
        term+dfn.gsub(', ', ",\n" + ' ' * term.length)
      }
      about.split("\n").each {|line| $x.pre line, :class => :stdout}
    elsif File.exist? 'script/rails'
      cmd 'ruby script/rails application -v'
    else
      cmd Gorp.which_rails($rails) + ' -v'
    end
 
    Dir.chdir(File.join($WORK, $rails_app.to_s)) do
      if $bundle
        cmd 'bundle show'
      else
        cmd 'gem list'
        cmd 'echo $RUBYLIB | sed "s/:/\n/g"'
      end
    end

    cmd 'gem -v'
    cmd "#{$ruby} -v"

    if not `which rvm`.empty?
      if ENV['rvm_version']
        cmd "echo $rvm_version", :as => 'rvm -v' 
      else
        cmd "rvm -v | grep '\\S'", :as => 'rvm -v' 
      end
    elsif not `which rbenv`.empty?
      cmd "rbenv --version"
    end

    if not `which nodejs`.empty?
      cmd "nodejs -v"
    elsif not `which node`.empty?
      cmd "node -v"
    end

    log :cmd, 'echo $PATH'
    $x.pre 'echo $PATH', :class=>'stdin'
    ENV['PATH'].split(':').each {|path| $x.pre path, :class => :stdout}

    if not `which lsb_release`.empty?
      cmd "lsb_release -irc"
    elsif File.exist? '/etc/debian_version'
      cmd 'cat /etc/debian_version'
    end

    if not `which sw_vers`.empty?
      cmd "sw_vers"
    end

    if not `which uname`.empty?
      cmd "uname -srm"
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
