# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RecurrenceSerializer do
  describe '.load' do
    it 'returns nil for nil input' do
      expect(described_class.load(nil)).to be_nil
    end

    it 'returns nil for empty string input' do
      expect(described_class.load('')).to be_nil
    end

    it 'returns a Recurrence object for a valid rrule string' do
      result = described_class.load('FREQ=DAILY;INTERVAL=1')
      expect(result).to be_a(Recurrence)
      expect(result.frequency).to eq('DAILY')
      expect(result.interval).to eq(1)
    end
  end

  describe '.dump' do
    it 'returns nil for nil input' do
      expect(described_class.dump(nil)).to be_nil
    end

    it 'returns the rrule string for a Recurrence object' do
      recurrence = Recurrence.new(frequency: 'WEEKLY', interval: 2, day_of_week: 'MO')
      expect(described_class.dump(recurrence)).to eq('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO')
    end
  end

  describe 'round-trip' do
    it 'preserves data through dump then load' do
      original = Recurrence.new(frequency: 'MONTHLY', interval: 3, date_of_month: 15)
      rrule_string = described_class.dump(original)
      restored = described_class.load(rrule_string)

      expect(restored.frequency).to eq(original.frequency)
      expect(restored.interval).to eq(original.interval)
      expect(restored.date_of_month).to eq(original.date_of_month)
      expect(restored.rrule).to eq(original.rrule)
    end
  end
end
