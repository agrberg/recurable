# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

require 'bundler/setup'
begin
  require 'debug'
rescue LoadError
  # debug gem is optional; available in the root Gemfile but not in CI matrix gemfiles
end
require 'active_support/all'
require 'recurable'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
