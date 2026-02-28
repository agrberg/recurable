# frozen_string_literal: true

require_relative 'lib/recurable/version'

Gem::Specification.new do |spec|
  spec.name = 'recurable'
  spec.version = Recurable::VERSION
  spec.authors = ['Aaron Rosenberg', 'Matt Lewis']
  spec.summary = 'iCal RRULE recurrence library with optional Rails integration'
  spec.description = <<~DESC
    Provides Recurrence, RruleAdapter, and RecurrenceSerializer as a standalone library
    for working with iCal RRULE recurrence patterns. Optionally integrates with Rails via
    the Recurable concern for transparent ActiveRecord serialization. Handles DST-safe
    projection for all frequencies from minutely through yearly.
  DESC

  spec.required_ruby_version = '>= 3.3'

  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['source_code_uri'] = 'https://github.com/agrberg/recurable'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/agrberg/recurable/issues'

  spec.files = Dir['lib/**/*', 'config/**/*', 'LICENSE', 'README.md']

  spec.add_dependency 'activemodel', '>= 7.1'
  spec.add_dependency 'activesupport', '>= 7.1'
  spec.add_dependency 'ice_cube',     '>= 0.16'
  spec.add_dependency 'rrule',        '>= 0.5'
end
