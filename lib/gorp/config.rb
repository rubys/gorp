require 'yaml'

#
# Support for per-environment overrides
#

module Gorp
  class Config
    @@hash = {}

    def self.load(config)
      config = File.expand_path(config)
      if File.exist? config
        @@hash.merge! YAML.load(File.read(config))
      end

      @@hash
    end

    def self.get
      hash = @@hash.dup

      rails = hash.delete('rails')
      if rails
        hash['rails'] = version = File.read("#$rails/RAILS_VERSION").chomp
        rails.each do |pattern, config|
          pattern = "#{pattern}.*" if pattern.instance_of? Numeric
          pattern = '^' + Regexp.escape(pattern.to_s).gsub('\*','.*?')
          if version =~ Regexp.new(pattern)
            hash.merge! config
          end
        end
      end

      ruby = hash.delete('ruby')
      if ruby
        hash['ruby'] = version = RUBY_VERSION 
        ruby.each do |pattern, config|
          pattern = "#{pattern}.*" if pattern.instance_of? Numeric
          pattern = '^' + Regexp.escape(pattern.to_s).gsub('\*','.*?')
          if version =~ Regexp.new(pattern)
            hash.merge! config
          end
        end
      end

      hash
    end

    def self.[](name, default=nil)
      hash = self.get
      if hash.has_key? name.to_s
        hash[name.to_s]
      else
        default
      end
    end
  end
end
