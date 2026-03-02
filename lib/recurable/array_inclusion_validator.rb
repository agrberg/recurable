# frozen_string_literal: true

require 'active_model'

class ArrayInclusionValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    allowed = options[:in]
    Array(value).each do |element|
      valid = allowed.is_a?(Regexp) ? allowed.match?(element) : allowed.include?(element)
      record.errors.add(attribute, "contains invalid value: #{element}") unless valid
    end
  end
end
