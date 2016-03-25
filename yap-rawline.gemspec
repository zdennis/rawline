# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "yap-rawline"
  s.version = "0.2.0"
  s.summary = %q{A library for defining custom key bindings and perform line editing operations}
  s.description = %q{RawLine can be used to define custom key bindings, perform common line editing operations, manage command history and define custom command completion rules. }
  s.email = %q{zach.dennis@gmail.com}
  s.homepage = %q{https://github.com/zdennis/rawline}
  s.authors = ["Fabio Cevasco", "Zach Dennis"]
  s.date = "2016-03-24"
  s.license = "MIT"
  s.files = Dir.glob("lib/**/*")
  s.files += Dir.glob("examples/*")
  s.files += Dir.glob("spec/*")
  s.files += ["README.rdoc", "LICENSE", "CHANGELOG.rdoc"]
  s.add_runtime_dependency 'highline', '~> 1.7', '>= 1.7.2'
  s.add_runtime_dependency("terminal-layout", ["~> 0.2.0"])
  s.add_runtime_dependency("term-ansicolor", ["~> 1.3.0"])
  s.add_development_dependency("rspec", ["~> 3.0"])
end
