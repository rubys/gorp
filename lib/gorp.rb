# The following is under the "I ain't too proud" school of programming.
# global variables, repetition, and brute force abounds.
#
# You have been warned.

require 'fileutils'
require 'open3'
require 'net/http'
require 'builder'
require 'stringio'
require 'time'
require 'cgi'

require 'gorp/env'
require 'gorp/edit'

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

# verify that port is available for testing
if (Net::HTTP.get_response('localhost','/',$PORT).code == '200' rescue false)
  STDERR.puts "local server already running on port #{$PORT}"
  exit
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

def snap response, form=nil
  if response.content_type == 'text/plain' or response.content_type =~ /xml/
    $x.div :class => 'body' do
      response.body.split("\n").each do |line| 
        $x.pre line.chomp, :class=>'stdout'
      end
    end
    return
  end

  if response.body =~ /<body/
    body = response.body
  else
    body = "<body>#{response.body}</body>"
  end

  begin
    doc = xhtmlparse(body)
  rescue
    body.split("\n").each {|line| $x.pre line.chomp, :class=>'hilight'}
    raise
  end

  title = doc.at('html/head/title').text rescue ''
  body = doc.at('//body')
  doc.search('//link[@rel="stylesheet"]').each do |sheet|
    body.children.first.add_previous_sibling(sheet)
  end

  if form
    body.search('//input[@name]').each do |input|
      input['value'] ||= form[input['name']].to_s
    end
    body.search('//textarea[@name]').each do |textarea|
      textarea.text = form[textarea['name']].to_s if textarea.text.to_s.empty?
    end
  end

  %w{ a[@href] form[@action] }.each do |xpath|
    name = xpath[/@(\w+)/,1]
    body.search("//#{xpath}").each do |element|
      next if element[name] =~ /^http:\/\//
      element[name] = URI.join("http://localhost:#{$PORT}/", element[name]).to_s
    end
  end

  %w{ img[@src] }.each do |xpath|
    name = xpath[/@(\w+)/,1]
    body.search("//#{xpath}").each do |element|
      if element[name][0] == ?/
        element[name] = 'data' + element[name]
      end
    end
  end

  body.search('//textarea').each do |element|
    element.content=''
  end

  attrs = {:class => 'body', :title => title}
  attrs[:class] = 'traceback' if response.code == '500'
  attrs[:id] = body['id'] if body['id']
  $x.div(attrs) do
    body.children.each do |child|
      $x << child.to_xml unless child.instance_of?(Comment)
    end
  end
  $x.div '', :style => "clear: both"
end

def get path
  post path, nil
end

def post path, form, options={}
  $x.pre "get #{path}", :class=>'stdin' unless options[:snapget] == false

  if path.include? ':'
    host, port, path = URI.parse(path).select(:host, :port, :path)
  else
    host, port = '127.0.0.1', $PORT
  end

  Net::HTTP.start(host, port) do |http|
    get = Net::HTTP::Get.new(path)
    get['Cookie'] = $COOKIE if $COOKIE
    response = http.request(get)
    snap response, form unless options[:snapget] == false
    $COOKIE = response.response['set-cookie'] if response.response['set-cookie']

    if form
      body = xhtmlparse(response.body).at('//body')
      body = xhtmlparse(response.body).root unless body
      xforms = body.search('//form')

      # find matching button by action
      xform = xforms.find do |element|
        next unless element.attribute('action').to_s.include?('?')
        query = CGI.parse(URI.parse(element.attribute('action').to_s).query)
        query.all? {|key,values| values.include?(form[key].to_s)}
      end

      # find matching button by input names
      xform ||= xforms.find do |element|
        form.all? do |name, value| 
          element.search('.//input | .//textarea | ..//select').any? do |input|
            input.attribute('name').to_s==name.to_s
          end
        end
      end

      # match based on action itself
      xform ||= xforms.find do |element|
        form.all? do |name, value| 
          element.attribute('action').to_s.include?(path)
        end
      end

      # look for a commit button
      xform ||= xforms.find {|element| element.at('.//input[@name="commit"]')}

      return unless xform

      path = xform.attribute('action').to_s unless
        xform.attribute('action').to_s.empty?
      $x.pre "post #{path}", :class=>'stdin'

      $x.ul do
        form.each do |name, value|
          $x.li "#{name} => #{value}"
        end

        xform.search('.//input[@type="hidden"]').each do |element|
          # $x.li "#{element['name']} => #{element['value']}"
          form[element['name']] ||= element['value']
        end
      end

      post = Net::HTTP::Post.new(path)
      post.form_data = form
      post['Cookie'] = $COOKIE
      response=http.request(post)
      snap response
    end

    if response.code == '302'
      $COOKIE=response.response['set-cookie'] if response.response['set-cookie']
      path = response['Location']
      $x.pre "get #{path}", :class=>'stdin'
      get = Net::HTTP::Get.new(path)
      get['Cookie'] = $COOKIE if $COOKIE
      response = http.request(get)
      snap response
      $COOKIE=response.response['set-cookie'] if response.response['set-cookie']
    end
  end
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

def which_rails rails
  railties = File.join(rails, 'railties', 'bin', 'rails')
  rails = railties if File.exists?(railties)
  if File.exists?(rails)
    firstline = open(rails) {|file| file.readlines.first}
    rails = 'ruby ' + rails unless firstline =~ /^#!/
  end
  rails
end

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
    begin
      if File.exist?('config.ru')
        require 'rack'
        server = Rack::Builder.new {eval open('config.ru').read}
        Rack::Handler::WEBrick.run(server, :Port => $PORT)
      else
        # start server, redirecting stdout to a string
        $stdout = StringIO.open('','w')
        require './config/boot'
        if Rails::VERSION::MAJOR == 2
          require 'commands/server'
        else
          require 'rails/commands/server'
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

at_exit do
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

      cmd which_rails($rails) + ' -v'
  
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
    if $checker =~ /^[-\w]+$/
      require File.join($BASE,$checker)
    else
      require $checker
    end
  end
end
