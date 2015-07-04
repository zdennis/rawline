#!/usr/bin/env ruby

task :default => :spec

# RSpec
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = 'spec/**/*_spec.rb'
    t.rspec_opts = ["-c", "-f progress"]
  end
  RSpec::Core::RakeTask.new(:test) do |t|
    args = ARGV.reverse
    args.pop
    t.pattern = args.join " "
    t.rspec_opts = ["-c", "-f progress"]
  end
rescue LoadError
  puts "RSpec is not available. Install it with: gem install rspec"
end

# Yard
begin
  require 'yard'
  YARD::Rake::YardocTask.new(:yardoc) do |t|
    t.files   = ['lib/**/*.rb', './README.rdoc', 'CHANGELOG.rdoc', 'lib/*.rb']
    t.options = ['--no-private']
  end
rescue LoadError
  puts "YARD is not available. Install it with: gem install yard"
end
