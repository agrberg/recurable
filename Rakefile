# frozen_string_literal: true

require 'rake'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Default: run specs and rubocop'
task default: %i[spec rubocop]

RSpec::Core::RakeTask.new { _1.pattern = './spec/**/*_spec.rb' }
RuboCop::RakeTask.new

desc 'Generate code coverage with simplecov'
task(:coverage) do
  system('COVERAGE=true bundle exec rspec') && system('open coverage/index.html')
end
