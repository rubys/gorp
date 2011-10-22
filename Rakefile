require 'rubygems'
require 'rake'
require 'echoe'

require File.expand_path(File.dirname(__FILE__) + "/lib/version")

Echoe.new('gorp', Gorp::VERSION::STRING) do |p|
  p.summary    = "Rails scenario testing support library"
  p.description    = <<-EOF
    Enables the creation of scenarios that involve creating a rails project,
    starting and stoppping of servers, generating projects, editing files,
    issuing http requests, running of commands, etc.  Output is captured as
    a single HTML file that can be viewed locally or uploaded.

    Additionally, there is support for verification, in the form of defining
    assertions based on selections (typically CSS) against the generated HTML.
  EOF
  p.url            = "http://github.com/rubys/gorp"
  p.author         = "Sam Ruby"
  p.email          = "rubys@intertwingly.net"
  p.dependencies   = %w(
    builder
    bundler
    i18n
    rack
    rake
  )
  # Does not include mail -- as it depends on active_support
  # test-unit -- incompatible with i18n one hash required (testrunner.rb:116)
end
