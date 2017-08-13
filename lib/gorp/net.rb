require 'net/http'
require 'cgi'
require 'http-cookie'
require 'pathname'
require 'fileutils'

$COOKIEJAR = HTTP::CookieJar.new
$CookieDebug = Gorp::Config[:cookie_debug]

def update_cookies(uri, response)
  fields = response.get_fields('Set-Cookie')
  return unless fields
  fields.each {|value| $COOKIEJAR.parse(value, uri)}

  if $CookieDebug
    $x.ul do
      fields.each do |value|
        $x.li do
          $x.b {$x.em '[cookie]'}
          $x.text! value.to_s
        end
      end
    end
  end
end

def snap response, form=nil
  if response.code >= '400'
    $x.p "HTTP Response Code: #{response.code}", :class => 'traceback'
  end

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
  elsif response.body =~ /<BODY/
    body = response.body.gsub(/<\/?\w+/) {|tag| tag.downcase}
    body.gsub! '<hr>', '<hr/>'
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

  # ensure that textareas don't use the self-closing syntax
  body.search('//textarea').each do |element|
    element.content=''
  end

  if form
    body.search('//input[@name]').each do |input|
      input['value'] ||= form[input['name']].to_s
    end
    body.search('//textarea[@name]').each do |textarea|
      textarea.content = form[textarea['name']].to_s if textarea.text.empty?
    end
  end

  %w{ a[@href] form[@action] }.each do |xpath|
    name = xpath[/@(\w+)/,1]
    body.search("//#{xpath}").each do |element|
      if element[name] =~ /^http:\/\//
        element[name] = element[name].sub('127.0.0.1', 'localhost')
      else
        element[name]=URI.join("http://localhost:#{$PORT}/", element[name]).to_s
      end
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

  attrs = {:class => 'body', :title => title}
  attrs[:class] = 'traceback' if response.code == '500'
  attrs[:id] = body['id'] if body['id']
  attrs[:class] += ' ' +body['class'] if body['class']
  $x.div(attrs) do
    html_voids = %w(area base br col command embed hr img input keygen link
                    meta param source)

    body.children.each do |child|
      next if child.instance_of?(Comment)
      child.search("//*").each do |element|
        next if html_voids.include? element.name
        if element.children.empty? and element.text.empty?
          element.add_child(Nokogiri::XML::Text.new('', element.document))
        end
      end
      $x << child.to_xml
    end
  end
  $x.div '', :style => "clear: both"
end

def get path, options={}
  post path, nil, options
end

# Take a screenshot using PhantomJS and screenshots.js if GORP_SCREENSHOTS is true in the environment.
#
# uri - the url to request initially, likely http://localhost:3000
# options - how to take the screenshot.
#           filename: path to the file where a PDF of the screenshot should be saved
#           dimensions: a 2d array of length x width of how large the screenshot should be.
#                       This isn't precise due to the nature of how PhantomJS saves PDFs, but generally
#                       it's better to specify values that might be too small, as it will stretch.
#           form_data: a hash of form data to fill in on the screen.  This is useful if you want a screenshot
#                      of a form filled in, but not submitted. Will not submit the form by default.
#           submit_form: if `true`, will expect exactly one form on the screen and will submit it, after
#                        filling in any form_data.  If the value is a number, it will submit that indexed
#                        form on the page (e.g. 1 -> first, 2 -> second).  Note that screenshot.js
#                        ONLY SUPPORTS 1.  So effectively, this should only be the number 1.  Sorry.
#           workflow: An array of magic strings that will click around the page and submit forms.  This is mutually
#                     exclusive with form_data and submit_form.  Each url in the array is a step to perform.
#                     screenshot.js assumes that the step will reload the page, so it waits for the page
#                     before moving on.
#
#                     By default, each string is assumed to be the URL in a form action.  screenshot.js will
#                     locate the form with that action and submit it.  If the url contains query string parameters,
#                     it will attempt to find those fields in the form and fill them in.  This only works if the 
#                     fields exist, so this doesn't post arbitrary data.
#
#                     If the string begins with `GET:`, then the workflow step is to simply set
#                     window.location to the url after `GET:`.
#
#                     I realize this is super janky and a total hack, but it works and let me solve the problem
#                     of making screenshots without going into a browser.  If you are wondering if it would've
#                     been easier to just hand-jam the screenshots—it probably would've been :(
def screenshot uri, options
  return unless ENV["GORP_SCREENSHOTS"] == "true"
  puts options.inspect
  images_dir = (Pathname("..") / "images").expand_path
  FileUtils.mkdir_p images_dir

  filename = (images_dir / options.fetch(:filename)).expand_path
  width    = Array(options[:dimensions])[0] || "default"
  height   = Array(options[:dimensions])[1] || "default"
  extra_args = if options[:form_data]
                 options[:form_data].map { |key,value|
                   value = value.to_s.gsub(/["']/,"").gsub("\\n","\n").split(/[\n\r]/).join("\\n")
                   "'#{key}=#{value}'"
                 }.join(" ")
               elsif options[:workflow]
                 "\"WORKFLOW:#{options[:workflow].join(',')}\""
               else
                 ""
               end
  if options[:submit_form] != nil
    if options[:submit_form] == true
      extra_args += " SUBMIT"
    else
      extra_args += " SUBMIT#{options[:submit_form]}"
    end
  end

  exe      = File.expand_path(File.join("..","..","screenshot.js"))
  command  = "phantomjs #{exe} #{uri} #{filename} #{width} #{height} #{extra_args}"
  puts command
  unless system(command)
    raise "Problem running '#{command}'"
  end
end

def post path, form, options={}
  $lastmod ||= Time.now
  log :get, path unless form
  $x.pre "get #{path}", :class=>'stdin' unless options[:snapget] == false

  if path.include? ':'
    host, port, path = URI.parse(path).select(:host, :port, :path)
  else
    host, port = 'localhost', $PORT
  end

  Net::HTTP.start(host, port) do |http|
    sleep 0.5 if Gorp::Config[:delay_post]

    accept = options[:accept] || 'text/html'
    accept = 'application/atom+xml' if path =~ /\.atom$/
    accept = 'application/json' if path =~ /\.json$/
    accept = 'application/xml' if path =~ /\.xml$/

    uri = URI.parse("http://#{host}:#{port}/#{path}")
    get = Net::HTTP::Get.new(path, 'Accept' => accept)
    get.basic_auth *options[:auth] if options[:auth]
    get['Cookie'] = HTTP::Cookie.cookie_value($COOKIEJAR.cookies(uri))
    response = http.request(get)
    snap response, form unless options[:snapget] == false
    if options[:screenshot]
      options[:screenshot][:form_data] ||= form
      screenshot uri, options[:screenshot]
    end
    update_cookies uri, response

    if form
      body = xhtmlparse(response.body).at('//body') rescue nil
      body = xhtmlparse(response.body).root unless body rescue nil
      return unless body
      xforms = body.search('//form')

      # find matching button by action
      xform = xforms.find do |element|
        next unless element['action'].include?('?')
        query = CGI.parse(URI.parse(element['action']).query)
        query.all? {|key,values| values.include?(form[key].to_s)}
      end

      # find matching button by input names
      xform ||= xforms.find do |element|
        form.all? do |name, value| 
          element.search('.//input | .//textarea | ..//select').any? do |input|
            input['name']==name.to_s
          end
        end
      end

      # find matching submit button
      xform ||= xforms.search('form').find do |element|
        form.all? do |name, value| 
          element.search('.//input[@type="submit"]').any? do |input|
            input['value']==form['submit']
          end
        end
      end

      # look for a data-method link
      if not xform and form.keys == [:method]
        link = body.at("//a[@data-method=#{form[:method].to_s.inspect}]")
        head = xhtmlparse(response.body).at('//head')
        xform = Nokogiri::XML::Node.new "form", head.document
        xform['action'] = link['href']
        input = Nokogiri::XML::Node.new "input", head.document
        input['type'] = 'hidden'
        input['name'] = '_method'
        input['value'] = form[:method].to_s
        xform << input
        input = Nokogiri::XML::Node.new "input", head.document
        input['type'] = 'hidden'
        input['name'] = head.at('meta[@name="csrf-param"]')['content']
        input['value'] = head.at('meta[@name="csrf-token"]')['content']
        xform << input
      end

      # match based on action itself
      xform ||= xforms.find do |element|
        action=CGI.unescape(element['action'])
        form.all? {|name, value| action.include? "#{name}=#{value}"}
      end

      # look for a commit button
      xform ||= xforms.find {|element| element.at('.//input[@name="commit"]')}

      return unless xform

      path = xform['action'] unless xform['action'].empty?
      path = CGI::unescapeHTML(path)
      $x.pre "post #{path}", :class=>'stdin'

      $x.ul do
        form.each do |name, value|
          $x.li "#{name} => #{value}" unless $CookieDebug
        end

        xform.search('.//input[@type="hidden"]').each do |element|
          $x.li "#{element['name']} => #{element['value']}" if $CookieDebug
          form[element['name']] ||= element['value']
        end

        if $CookieDebug
          uri = URI.parse("http://#{host}:#{port}/#{path}")
          $COOKIEJAR.cookies(uri).each do |cookie|
            $x.li do
              $x.b {$x.em '[cookie]'}
              $x.text! cookie.to_s
            end
          end

          head = xhtmlparse(response.body).at('//head')
          $x.li do
            $x.b {$x.em '[meta]'}
            $x.text! 'csrf-param => '
            $x.text! head.at('meta[@name="csrf-param"]')['content']
          end
          $x.li do
            $x.b {$x.em '[meta]'}
            $x.text! 'csrf-token => '
            $x.text! head.at('meta[@name="csrf-token"]')['content']
          end
        end
      end

      # workaround Rails 5 beta bug
      # https://github.com/rails/rails/issues/23524
      if Gorp::Config[:override_form_token]
        head = xhtmlparse(response.body).at('//head')
        form[head.at('meta[@name="csrf-param"]')['content']] = 
          head.at('meta[@name="csrf-token"]')['content']
      end

      log :post, path
      uri = URI.parse("http://#{host}:#{port}/#{path}")
      post = Net::HTTP::Post.new(path)
      post.set_form_data form
      post['Content-Type'] = 'application/x-www-form-urlencoded'
      post['Cookie'] = HTTP::Cookie.cookie_value($COOKIEJAR.cookies(uri))
      response=http.request(post)
      snap response
      update_cookies uri, response
    end

    if response.code == '302'
      path = response['Location']
      uri = URI.parse("http://#{host}:#{port}/#{path}")
      $x.pre "get #{path}", :class=>'stdin'
      get = Net::HTTP::Get.new(path, 'Accept' => accept)
      get['Cookie'] = HTTP::Cookie.cookie_value($COOKIEJAR.cookies(uri))
      response = http.request(get)
      snap response
      update_cookies uri, response
    end
  end
rescue Timeout::Error
  Gorp::Commands.stop_server(false, 9)
ensure 
  while true
    open('tmp/lastmod', 'w') {|file| file.write 'data'}
    break if File.mtime('tmp/lastmod') > $lastmod
    sleep 0.1
  end
  File.unlink('tmp/lastmod')
end
