require "bundler/gem_tasks"
require "term/ansicolor"

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

namespace :release do
  desc "Release check"
  task :check do
    current_branch = `git branch | grep '*' | sed -e 's/^*\ //'`.chomp

    is_dirty = `git diff --shortstat 2> /dev/null`.length > 0
    is_on_master = current_branch == 'master'
    most_recent_tag = `git tag -l --sort creatordate`.lines.last.chomp
    most_recent_commit = `git log -n1 --format="%H"`.chomp
    tag_matches_head = `git diff #{most_recent_tag}..HEAD 2> /dev/null`.length == 0
    latest_gem = `echo $(cd pkg && ls -rt1 *.gem | tail -1) 2> /dev/null`.chomp
    gem_version = latest_gem.scan(/\d+\.\d+\.\d+/).flatten.first

    print "Ready to release (#{latest_gem})? "
    if tag_matches_head
      puts Term::ANSIColor.green("\u2713")
    elsif is_dirty
      puts Term::ANSIColor.red("\u2718")
      puts Term::ANSIColor.red("  uncommitted changes")
    else
      puts Term::ANSIColor.red("\u2718")
      puts Term::ANSIColor.red("  untagged changes")
    end
  end
end
