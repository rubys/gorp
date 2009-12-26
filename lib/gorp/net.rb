require 'net/http'
require 'cgi'

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
