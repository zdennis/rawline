# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rawline/version'

Gem::Specification.new do |s|
  s.name = "yap-rawline"
  s.version = RawLine::VERSION
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

  s.add_dependency "ansi_string", "~> 0.1"
  s.add_dependency "highline", "~> 1.7", ">= 1.7.2"
  s.add_dependency "terminal-layout", "~> 0.4.2"
  s.add_dependency "term-ansicolor", "~> 1.3.0"

  s.add_development_dependency "rspec", "~> 3.0"
end
