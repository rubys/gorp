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
