# frozen_string_literal: true

require 'active_model'

class ArrayInclusionValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    Array(value).each do |element|
      record.errors.add(attribute, "contains invalid value: #{element}") unless options[:in].include?(element)
    end
  end
end
