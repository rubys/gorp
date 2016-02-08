# -*- encoding: utf-8 -*-
# stub: gorp 0.28.2 ruby lib

Gem::Specification.new do |s|
  s.name = "gorp"
  s.version = "0.28.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Sam Ruby"]
  s.date = "2016-02-02"
  s.description = "    Enables the creation of scenarios that involve creating a rails project,\n    starting and stoppping of servers, generating projects, editing files,\n    issuing http requests, running of commands, etc.  Output is captured as\n    a single HTML file that can be viewed locally or uploaded.\n\n    Additionally, there is support for verification, in the form of defining\n    assertions based on selections (typically CSS) against the generated HTML.\n"
  s.email = "rubys@intertwingly.net"
  s.extra_rdoc_files = ["README", "lib/gorp.rb", "lib/gorp/commands.rb", "lib/gorp/edit.rb", "lib/gorp/env.rb", "lib/gorp/net.rb", "lib/gorp/output.css", "lib/gorp/output.rb", "lib/gorp/rails.env", "lib/gorp/rails.rb", "lib/gorp/test.rb", "lib/gorp/xml.rb", "lib/version.rb"]
  s.files = ["Manifest", "README", "Rakefile", "gorp.gemspec", "lib/gorp.rb", "lib/gorp/commands.rb", "lib/gorp/edit.rb", "lib/gorp/env.rb", "lib/gorp/net.rb", "lib/gorp/output.css", "lib/gorp/output.rb", "lib/gorp/rails.env", "lib/gorp/rails.rb", "lib/gorp/test.rb", "lib/gorp/xml.rb", "lib/version.rb"]
  s.homepage = "http://github.com/rubys/gorp"
  s.rdoc_options = ["--line-numbers", "--title", "Gorp", "--main", "README"]
  s.rubyforge_project = "gorp"
  s.rubygems_version = "2.5.1"
  s.summary = "Rails scenario testing support library"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<builder>, [">= 0"])
      s.add_runtime_dependency(%q<bundler>, [">= 0"])
      s.add_runtime_dependency(%q<i18n>, [">= 0"])
      s.add_runtime_dependency(%q<rack>, [">= 0"])
      s.add_runtime_dependency(%q<rake>, [">= 0"])
      s.add_runtime_dependency(%q<http-cookie>, [">= 0"])
    else
      s.add_dependency(%q<builder>, [">= 0"])
      s.add_dependency(%q<bundler>, [">= 0"])
      s.add_dependency(%q<i18n>, [">= 0"])
      s.add_dependency(%q<rack>, [">= 0"])
      s.add_dependency(%q<rake>, [">= 0"])
      s.add_dependency(%q<http-cookie>, [">= 0"])
    end
  else
    s.add_dependency(%q<builder>, [">= 0"])
    s.add_dependency(%q<bundler>, [">= 0"])
    s.add_dependency(%q<i18n>, [">= 0"])
    s.add_dependency(%q<rack>, [">= 0"])
    s.add_dependency(%q<rake>, [">= 0"])
    s.add_dependency(%q<http-cookie>, [">= 0"])
  end
end
