# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{gorp}
  s.version = "0.13.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sam Ruby"]
  s.date = %q{2009-12-16}
  s.description = %q{    Enables the creation of scenarios that involve creating a rails project,
    starting and stoppping of servers, generating projects, editing files,
    issuing http requests, running of commands, etc.  Output is captured as
    a single HTML file that can be viewed locally or uploaded.

    Additionally, there is support for verification, in the form of defining
    assertions based on selections (typically CSS) against the generated HTML.
}
  s.email = %q{rubys@intertwingly.net}
  s.extra_rdoc_files = ["README", "lib/gorp.rb", "lib/gorp/env.rb", "lib/gorp/test.rb", "lib/version.rb"]
  s.files = ["Manifest", "README", "Rakefile", "gorp.gemspec", "lib/gorp.rb", "lib/gorp/env.rb", "lib/gorp/test.rb", "lib/version.rb"]
  s.homepage = %q{http://github.com/rubys/gorp}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Gorp", "--main", "README"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{gorp}
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{Rails scenario testing support library}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<builder>, [">= 0"])
      s.add_runtime_dependency(%q<erubis>, [">= 0"])
      s.add_runtime_dependency(%q<rack>, [">= 0"])
      s.add_runtime_dependency(%q<rack-mount>, [">= 0"])
      s.add_runtime_dependency(%q<rack-test>, [">= 0"])
      s.add_runtime_dependency(%q<rake>, [">= 0"])
      s.add_runtime_dependency(%q<sqlite3-ruby>, [">= 0"])
      s.add_runtime_dependency(%q<tzinfo>, [">= 0"])
    else
      s.add_dependency(%q<builder>, [">= 0"])
      s.add_dependency(%q<erubis>, [">= 0"])
      s.add_dependency(%q<rack>, [">= 0"])
      s.add_dependency(%q<rack-mount>, [">= 0"])
      s.add_dependency(%q<rack-test>, [">= 0"])
      s.add_dependency(%q<rake>, [">= 0"])
      s.add_dependency(%q<sqlite3-ruby>, [">= 0"])
      s.add_dependency(%q<tzinfo>, [">= 0"])
    end
  else
    s.add_dependency(%q<builder>, [">= 0"])
    s.add_dependency(%q<erubis>, [">= 0"])
    s.add_dependency(%q<rack>, [">= 0"])
    s.add_dependency(%q<rack-mount>, [">= 0"])
    s.add_dependency(%q<rack-test>, [">= 0"])
    s.add_dependency(%q<rake>, [">= 0"])
    s.add_dependency(%q<sqlite3-ruby>, [">= 0"])
    s.add_dependency(%q<tzinfo>, [">= 0"])
  end
end
