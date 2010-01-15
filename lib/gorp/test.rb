require 'test/unit'
require 'builder'
require 'gorp/env'
require 'gorp/rails'
require 'gorp/commands'

class Gorp::TestCase < Test::Unit::TestCase
  def self.suite
    # Deferred loading of Rails infrastructure
    if File.exist? "#{$WORK}/vendor/gems/environment.rb"
      require "#{$WORK}/vendor/gems/environment.rb"
    end

    require 'active_support'
    require 'active_support/version'
    require 'active_support/test_case'

    # just enough infrastructure to get 'assert_select' to work
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
    super
  end

  def self.test(name, &block)
    define_method("test_#{name.gsub(/\s+/,'_')}".to_sym) do
      self.class.herald self, name
      instance_eval &block
    end
  end

  def self.herald instance, name
  end

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
    info[:list] ||= :rails

    fail "Ticket #{info[:list]}:#{number}: #{info[:title]}"
  end

  # read and pre-process $input.html (only done once, and cached)
  def self.input filename
    # read $input output; remove front matter and footer
    input = open(File.join($WORK, "#{filename}.html")).read
    input.force_encoding('utf-8') if input.respond_to? :force_encoding
    head, body, tail = input.split /<body>\s+|\s+<\/body>/m

    # ruby 1.8.8 reverses the order
    body.gsub! /<a (id="[-.\w]+") (class="\w+")>/,'<a \2 \1>'

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

  %w(cmd get post rake ruby).each do |method|
    define_method(method) do |*args, &block|
      before = $x.target.length
      @@base.send method, *args
  
      if block
        @raw = $x.target![before..-1]
        @selected = HTML::Document.new(@raw).root.children
        block.call
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
    if $standalone
      puts fault
      x = $x
    else
      x = Builder::XmlMarkup.new(:indent => 2)
    end

    if fault.respond_to? :location
      x.pre fault.message.sub(".\n<false> is not true",'') +
        "\n\nTraceback:\n  " + fault.location.join("\n  "),
        :class=>'traceback'
    else
      if fault.message =~ /RuntimeError: Ticket (\w+):(\d+): (.*)/ 
        x.p :class => 'traceback' do
          x.a "Ticket #{$2}", :href => tickets[$1]+$2
          x.text! ': ' + $3
        end
      else
        x.pre fault.message, :class=>'traceback'
      end
    end

    if fault.test_name =~ /^test_([\d.]+)_.*\(\w+\)$/
      name = $1
      sections = @@sections
      return unless sections.has_key? name

      # indicate failure in the toc
      sections[:contents][/<a href="#section-#{name}"()>/,1] = 
        ' style="color:red; font-weight:bold"'

      tickets = {
        'rails' => 'https://rails.lighthouseapp.com/projects/8994/tickets/',
        'ruby'  => 'http://redmine.ruby-lang.org/issues/show/'
      }

      # provide details in the section itself
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
    # terminate server
    Gorp::Commands.stop_server

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

      if sections.empty?
        output.write($x.target!)
      end

      if env
        output.write('<a class="toc" id="env">')
        output.write(env)
      else
        $x = Builder::XmlMarkup.new(:indent => 2)
        $x.a(:class => 'toc', :id => 'env') {$x.h2 'Environment'}
        $stdout = StringIO.open('','w')
        Gorp.dump_env
        $stdout = STDOUT
        output.write($x.target!)
      end

      if todos
        output.write('<a class="toc" id="todos">')
        todos.sub! /<ul.*\/ul>/m, '<h2>None!</h2>' unless todos.include? '<li>'
        output.write(todos)
      end
      output.write("\n  </body>")
      output.write(tail)
    end

    open(File.join($WORK, 'status'), 'w') do |status|
      status.puts @result.to_s
    end

    at_exit { raise SystemExit.new(1) } unless @result.passed?
  end
end

# Produce output for standalone scripts
at_exit do
  next if $output
  $standalone = true

  if caller and !caller.empty?
    source = File.basename(caller.first.split(':').first)
  else
    source = File.basename($0).split('.').first
  end

  name = source.sub(Regexp.new(Regexp.escape(File.extname(source))+'$'), '')
  $output = name

  suite = Test::Unit::TestSuite.new(name)
  ObjectSpace.each_object(Class) do |c|
    next unless c.superclass == Gorp::TestCase
    suite << c.suite
    def c.herald instance, name
      instance.head nil, name
    end
  end

  def suite.sections
    style = open(File.join(File.dirname(__FILE__), 'output.css')) {|fh| fh.read}
    head = "<html>\n<head>\n<title>#{$output}</title>\n<style></style>\n</head>"
    $cleanup = Proc.new do
      Dir['public/stylesheets/*.css'].each do |css|
        File.open(css) {|file| style+= file.read}
      end
      head[/(<style><\/style>)/,1] = "<style>\n#{style}</style>"
    end
    {:head=>head, :tail=>"\n</html>"}
  end 

  require 'gorp/xml'
  require 'gorp/edit'
  require 'gorp/net'

  class HTMLRunner
    def output(something, *args)
     if something.respond_to?(:passed?)
       Gorp::Commands.stop_server
       at_exit {puts "\n#{something}"}
     end
    end
    def output_single(something, *args)
    end
  end

  HTMLRunner.run(suite)

  Gorp.log :WRITE, Gorp.path($output+'.html')
end
