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
      text.gsub! /<script[ >](.*?)<\/script>/m do
        '<script>' + $1.gsub('<','&lt;') + '</script>'
      end
      text.gsub! '&amp;', '&amp;amp;'
      text.gsub! '&lt;', '&amp;lt;'
      text.gsub! '&gt;', '&amp;gt;'
      text.gsub! '&apos;', '&amp;apos;'
      text.gsub! '&quot;', '&amp;quot;'
      text.force_encoding('utf-8') if text.respond_to? :force_encoding
      text = HTMLEntities.new.decode(text)
    rescue LoadError
    end
    text.gsub! '<br>', '<br/>'
    text.gsub! 'data-no-turbolink>', 'data-no-turbolink="data-no-turbolink">'
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
