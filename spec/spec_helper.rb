# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

require 'bundler/setup'
require 'active_support/all'
require 'recurable'

# Load the gem's default locale so recurrence_statement works in specs
I18n.load_path += Dir["#{__dir__}/../config/locales/*.yml"]
I18n.default_locale = :en

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
