require "bundler/gem_tasks"

Dir[File.join(File.dirname(__FILE__), 'lib/tasks/**/*.rake')].each {|f| load f }

task :default => :spec


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
