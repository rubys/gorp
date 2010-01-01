require 'test/unit'
require 'builder'
require 'gorp/env'
require 'gorp/rails'
require 'gorp/commands'

$:.unshift "#{$WORK}/rails/activesupport/lib"
  require 'active_support'
  require 'active_support/version'
  require 'active_support/test_case'
$:.shift

module Gorp
  class BuilderTee < BlankSlate
    def initialize(one, two)
      @one = one
      @two = two
    end

    def method_missing sym, *args, &block
      @one.method_missing sym, *args, &block
      @two.method_missing sym, *args, &block
    end
  end
end

class Gorp::TestCase < ActiveSupport::TestCase
  # just enough infrastructure to get 'assert_select' to work
  $:.unshift "#{$WORK}/rails/actionpack/lib"
  require 'action_controller'
  begin
    # Rails (2.3.3 ish)
    require 'action_controller/assertions/selector_assertions'
    include ActionController::Assertions::SelectorAssertions
  rescue LoadError
    # Rails (3.0 ish)
    require 'action_dispatch/testing/assertions'
  require 'action_dispatch/testing/assertions/selector'
    include ActionDispatch::Assertions::SelectorAssertions
  end
  require 'action_controller/vendor/html-scanner/html/tokenizer'
  require 'action_controller/vendor/html-scanner/html/document'

  # micro DSL allowing the definition of optional tests
  def self.section number, title, &tests
    number = (sprintf "%f", number).sub(/0+$/,'') if number.kind_of? Float
    return if @@omit.include? number.to_s
    test "#{number} #{title}" do
      instance_eval {select number}
      begin
        instance_eval &tests
      ensure
        unless $!.instance_of? RuntimeError
          @raw =~ /<pre\sclass="stdin">edit\s([\w\/.]+)<\/pre>\s+
                   <pre\sclass="traceback">\s+
                   \#&lt;IndexError:\sregexp\snot\smatched&gt;\s+
                   (.*gorp\/lib\/gorp\/edit.rb.*\n\s+)*
                   ([\w\/.]+:\d+)/x
          fail "Edit #{$1} failed at #{$3}" if $1
        end
      end
    end
  end

  def ticket number, info
    return if info[:match] and not @raw =~ info[:match]
    return if block_given? and not yield(@raw)

    fail "Ticket #{number}: #{info[:title]}"
  end

  # read and pre-process $input.html (only done once, and cached)
  def self.input filename
    # read $input output; remove front matter and footer
    input = open(File.join($WORK, "#{filename}.html")).read
    input.force_encoding('utf-8') if input.respond_to? :force_encoding
    head, body, tail = input.split /<body>\s+|\s+<\/body>/m

    # split into sections
    @@sections = body.split(/<a class="toc" id="section-(.*?)">/)
    @@sections[-1], env = @@sections.last.split(/<a class="toc" id="env">/)
    env, todos = env.split(/<a class="toc" id="todos">/)

    # split into sections
    @@omit = body.split(/<a class="omit" id="section-(.*?)">/)

    # convert to a Hash
    @@sections = Hash[*@@sections.unshift(:contents)]
    @@sections[:head] = head
    @@sections[:todos] = todos
    @@sections[:env] = env
    @@sections[:tail] = tail

    # reattach anchors
    @@sections.each do |key,value|
      next unless key =~ /^\d/
      @@sections[key] = "<a class=\"toc\" name=\"section-#{key}\">#{value}"
    end

    # report version
    body =~ /rails .*?-v<\/pre>\s+.*?>(.*)<\/pre>/
    @@version = $1
    @@version += ' (git)'    if body =~ /"stdin">ln -s.*vendor.rails</
    @@version += ' (edge)'   if body =~ /"stdin">rails:freeze:edge</
    @@version += ' (bundle)' if body =~ /"stdin">gem bundle</
    STDERR.puts @@version
  end

  def self.output filename
    $output = filename
    at_exit { HTMLRunner.run(self) }
  end

  # select an individual section from the HTML
  def select number
    raise "Section #{number} not found" unless @@sections.has_key? number.to_s
    @raw = @@sections[number.to_s]
    @selected = HTML::Document.new(@raw).root.children
  end

  attr_reader :raw

  def collect_stdout
    css_select('.stdout').map do |tag|
      tag.children.join.gsub('&lt;','<').gsub('&gt;','>')
    end
  end

  def sort_hash line
    line.sub(/^(=> )?\{.*\}$/) do |match|
      "#{$1}{#{match.scan(/:?"?\w+"?=>[^\[].*?(?=, |\})/).sort.join(', ')}}"
    end
  end

  def self.sections
    @@sections
  end 

  @@base = Object.new.extend(Gorp::Commands)
  include Gorp::Commands

  %w(cmd rake).each do |method|
    define_method(method) do |*args, &block|
      begin
        $y = Builder::XmlMarkup.new(:indent => 2)
        $x = Gorp::BuilderTee.new($x, $y)
        @@base.send method, *args

        if block
          @raw = $x.target!
          @selected = HTML::Document.new(@raw).root.children
          block.call
        end
      ensure
        $x = $x.instance_eval { @one }
      end
    end
  end
end

# insert failure indicators into #{output}.html
require 'test/unit/ui/console/testrunner'
class HTMLRunner < Test::Unit::UI::Console::TestRunner
  def self.run suite
    @@sections = suite.sections
    super
  end

  def attach_to_mediator
    super
    @html_tests = []
    @mediator.add_listener(Test::Unit::TestResult::FAULT,
      &method(:html_fault))
    @mediator.add_listener(Test::Unit::UI::TestRunnerMediator::FINISHED,
      &method(:html_summary))
  end

  def html_fault fault
    if fault.test_name =~ /^test_([\d.]+)_.*\(\w+\)$/
      name = $1
      sections = @@sections
      return unless sections.has_key? name

      # indicate failure in the toc
      sections[:contents][/<a href="#section-#{name}"()>/,1] = 
        ' style="color:red; font-weight:bold"'

      tickets = 'https://rails.lighthouseapp.com/projects/8994/tickets/'

      # provide details in the section itself
      x = Builder::XmlMarkup.new(:indent => 2)
      if fault.respond_to? :location
        x.pre fault.message.sub(".\n<false> is not true",'') +
          "\n\nTraceback:\n  " + fault.location.join("\n  "),
          :class=>'traceback'
      else
        if fault.message =~ /RuntimeError: Ticket (\d+): (.*)/ 
          x.p :class => 'traceback' do
            x.a "Ticket #{$1}", :href => tickets+$1
            x.text! ': ' + $2
          end
        else
          x.pre fault.message, :class=>'traceback'
        end
      end
      sections[name][/<\/a>()/,1] = x.target!

      # add to the todos
      x = Builder::XmlMarkup.new(:indent => 2)
      x.li do
        x.a "Section #{name}", :href => "#section-#{name}"
        if fault.message =~ /RuntimeError: Ticket (\d+): (.*)/ 
          x.text! '['
          x.a "Ticket #{$1}", :href => tickets+$1
          x.text! ']: ' + $2
        else
          x.text! ': '
          x.tt fault.message.sub(".\n<false> is not true",'').
            sub(/ but was\n.*/, '.').
            sub(/"((?:\\"|[^"])+)"/) {
              '"' + ($1.length>80 ? $1[0..72]+'...' : $1) + '"'
            }
        end
      end
      sections[:todos][/() *<\/ul>/,1] = x.target!.gsub(/^/,'      ')
    end
  end

  def html_summary elapsed
    open(File.join($WORK, "#{$output}.html"),'w') do |output|
      sections = @@sections
      output.write(sections.delete(:head))
      output.write("<body>\n    ")
      output.write(sections.delete(:contents))
      env = sections.delete(:env)
      todos = sections.delete(:todos)
      tail = sections.delete(:tail)
      sections.keys.sort_by {|key| key.split('.').map {|n| n.to_i}}.each do |n|
        output.write(sections[n])
      end
      output.write('<a class="toc" id="env">')
      output.write(env)
      output.write('<a class="toc" id="todos">')
      todos.sub! /<ul.*\/ul>/m, '<h2>None!</h2>' unless todos.include? '<li>'
      output.write(todos)
      output.write("\n  </body>")
      output.write(tail)
    end

    open(File.join($WORK, 'status'), 'w') do |status|
      status.puts @result.to_s
    end

    at_exit { raise SystemExit.new(1) } unless @result.passed?
  end
end
