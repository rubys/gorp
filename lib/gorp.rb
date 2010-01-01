# The following is under the "I ain't too proud" school of programming.
# global variables, repetition, and brute force abounds.
#
# You have been warned.

require 'fileutils'
require 'builder'

require 'gorp/env'
require 'gorp/commands'
require 'gorp/edit'
require 'gorp/output'
require 'gorp/net'
require 'gorp/rails'
require 'gorp/xml'

require 'rbconfig'
$ruby = File.join(Config::CONFIG["bindir"], Config::CONFIG["RUBY_INSTALL_NAME"])

# indicate that a given step should be omitted
def omit *sections
  sections.each do |section|
    section = [section] unless section.respond_to? :include?
    $omit << Range.new(secsplit(section.first), secsplit(section.last))
  end
end

# Micro DSL for declaring an ordered set of book sections
$sections = []
def section number, title, &steps
  number = (sprintf "%f", number).sub(/0+$/,'') if number.kind_of? Float
  $sections << [number, title, steps]
end

$x = Builder::XmlMarkup.new(:indent => 2)
$toc = Builder::XmlMarkup.new(:indent => 2)
$todos = Builder::XmlMarkup.new(:indent => 2)
$issue = 0
$style = Builder::XmlMarkup.new(:indent => 2)
$omit  = []

FileUtils.mkdir_p $WORK
RUNFILE = File.join($WORK, 'status.run')
open(RUNFILE,'w') {|running| running.puts(Process.pid)}
at_exit { FileUtils.rm_f RUNFILE }

def secsplit section
  section.to_s.split('.').map {|n| n.to_i}
end

def secinclude ranges, section
  # was (in Ruby 1.8): range.include?(secsplit(section))
  ranges.any? do |range| 
    ss = secsplit(section)
    (range.first <=> ss) <= 0 and (range.last <=> ss) >= 0
  end
end
