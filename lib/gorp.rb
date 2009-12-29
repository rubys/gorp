# The following is under the "I ain't too proud" school of programming.
# global variables, repetition, and brute force abounds.
#
# You have been warned.

require 'fileutils'
require 'open3'
require 'builder'
require 'time'

require 'gorp/env'
require 'gorp/edit'
require 'gorp/output'
require 'gorp/net'
require 'gorp/rails'

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

def overview message
  $x.p message.gsub(/(^|\n)\s+/, ' ').strip, :class=>'overview'
end

def desc message
  $x.p message, :class=>'desc'
end

def log type, message
  type = type.to_s.ljust(5).upcase
  STDOUT.puts Time.now.strftime("[%Y-%m-%d %H:%M:%S] #{type} #{message}")
end

def head number, title
  $section = "#{number} #{title}"
  log '====>', $section

  $x.a(:class => 'toc', :id => "section-#{number}") {$x.h2 $section}
  $toc.li {$toc.a $section, :href => "#section-#{number}"}
end

def issue text, options={}
  log :issue, text

  $issue+=1
  $x.p :class => 'issue', :id => "issue-#{$issue}" do
    $x.text! text
    if options[:ticket]
      $x.text! ' ('
      $x.a "ticket #{options[:ticket]}", :href=>
        'https://rails.lighthouseapp.com/projects/8994/tickets/' + 
        options[:ticket].to_s
      $x.text! ')'
    end
  end
  $todos.li do
    section = $section.split(' ').first
    $todos.a "Section #{section}:", :href => "#section-#{$section}"
    $todos.a "#{text}", :href => "#issue-#{$issue}"
  end
end

def db statement, hilight=[]
  log :db, statement
  $x.pre "sqlite3> #{statement}", :class=>'stdin'
  cmd = "sqlite3 --line db/development.sqlite3 #{statement.inspect}"
  popen3 cmd, hilight
end

def ruby args
  cmd "ruby #{args}"
end

def console script
  open('tmp/irbrc','w') {|file| file.write('IRB.conf[:PROMPT_MODE]=:SIMPLE')}
  cmd "echo #{script.inspect} | IRBRC=tmp/irbrc ruby script/console"
  FileUtils.rm_rf 'tmp/irbrc'
end

def cmd args, hilight=[]
  log :cmd, args
  $x.pre args, :class=>'stdin'
  if args == 'rake db:migrate'
    Dir.chdir 'db/migrate' do
      date = '20100301000000'
      Dir['[0-9]*'].sort_by {|file| file=~/201003/?file:'x'+file}.each do |file|
        file =~ /^([0-9]*)_(.*)$/
        FileUtils.mv file, "#{date}_#{$2}" unless $1 == date.next!
        $x.pre "mv #{file} #{date}_#{$2}"  unless $1 == date
      end
    end
  end
  args += ' -C' if args == 'ls -p'
  popen3 args, hilight
end

def popen3 args, hilight=[]
  Open3.popen3(args) do |pin, pout, perr|
    terr = Thread.new do
      $x.pre perr.readline.chomp, :class=>'stderr' until perr.eof?
    end
    pin.close
    until pout.eof?
      line = pout.readline
      if hilight.any? {|pattern| line.include? pattern}
        outclass='hilight'
      elsif line =~ /\x1b\[\d/
        line.gsub! /\x1b\[1m\x1b\[3\dm(.*?)\x1b\[0m/, '\1'
        outclass = 'logger'
      else
        outclass='stdout'
      end

      if line.strip.size == 0
        $x.pre ' ', :class=>outclass
      else
        $x.pre line.chomp, :class=>outclass
      end
    end
    terr.join
  end
end

def irb file
  $x.pre "irb #{file}", :class=>'stdin'
  log :irb, file
  cmd = "irb -f -rubygems -r ./config/boot --prompt-mode simple #{$CODE}/#{file}"
  Open3.popen3(cmd) do |pin, pout, perr|
    terr = Thread.new do
      until perr.eof?
        line = perr.readline.chomp
        line.gsub! /\x1b\[4(;\d+)*m(.*?)\x1b\[0m/, '\2'
        line.gsub! /\x1b\[0(;\d+)*m(.*?)\x1b\[0m/, '\2'
        line.gsub! /\x1b\[0(;\d+)*m/, ''
        $x.pre line, :class=>'stderr'
      end
    end
    pin.close
    prompt = nil
    until pout.eof?
      line = pout.readline
      if line =~ /^([?>]>)\s*#\s*(START|END):/
        prompt = $1
      elsif line =~ /^([?>]>)\s+$/
        $x.pre ' ', :class=>'irb'
        prompt ||= $1
      elsif line =~ /^([?>]>)(.*)\n/
        prompt ||= $1
        $x.pre prompt + $2, :class=>'irb'
	prompt = nil
      elsif line =~ /^\w+(::\w+)*: /
        $x.pre line.chomp, :class=>'stderr'
      elsif line =~ /^\s+from [\/.:].*:\d+:in `\w.*'\s*$/
        $x.pre line.chomp, :class=>'stderr'
      else
        $x.pre line.chomp, :class=>'stdout'
      end
    end
    terr.join
  end
end

# pluggable XML parser support
begin
  raise LoadError if ARGV.include? 'rexml'
  require 'nokogiri'
  def xhtmlparse(text)
    Nokogiri::HTML(text)
  end
  Comment=Nokogiri::XML::Comment
rescue LoadError
  require 'rexml/document'

  HTML_VOIDS = %w(area base br col command embed hr img input keygen link meta
                  param source)

  def xhtmlparse(text)
    begin
      require 'htmlentities'
      text.gsub! '&amp;', '&amp;amp;'
      text.gsub! '&lt;', '&amp;lt;'
      text.gsub! '&gt;', '&amp;gt;'
      text.gsub! '&apos;', '&amp;apos;'
      text.gsub! '&quot;', '&amp;quot;'
      text.force_encoding('utf-8') if text.respond_to? :force_encoding
      text = HTMLEntities.new.decode(text)
    rescue LoadError
    end
    doc = REXML::Document.new(text)
    doc.get_elements('//*[not(* or text())]').each do |e|
      e.text='' unless HTML_VOIDS.include? e.name
    end
    doc
  end

  class REXML::Element
    def has_attribute? name
      self.attributes.has_key? name
    end

    def at xpath
      self.elements[xpath]
    end

    def search xpath
      self.elements.to_a(xpath)
    end

    def content=(string)
      self.text=string
    end

    def [](index)
      if index.instance_of? String
        self.attributes[index]
      else
        super(index)
      end
    end

    def []=(index, value)
      if index.instance_of? String
        self.attributes[index] = value
      else
        super(index, value)
      end
    end
  end

  module REXML::Node
    def before(node)
      self.parent.insert_before(self, node)
    end

    def add_previous_sibling(node)
      self.parent.insert_before(self, node)
    end

    def to_xml
      self.to_s
    end
  end

  # monkey patch for Ruby 1.8.6
  doc = REXML::Document.new '<doc xmlns="ns"><item name="foo"/></doc>'
  if not doc.root.elements["item[@name='foo']"]
    class REXML::Element
      def attribute( name, namespace=nil )
        prefix = nil
        prefix = namespaces.index(namespace) if namespace
        prefix = nil if prefix == 'xmlns'
        attributes.get_attribute( "#{prefix ? prefix + ':' : ''}#{name}" )
      end
    end
  end

  Comment = REXML::Comment
end

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
