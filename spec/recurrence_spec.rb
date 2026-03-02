# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recurrence do
  describe 'constants' do
    it 'exposes FREQUENCIES in order with named constants' do
      expect(described_class::FREQUENCIES.keys).to eq %w[YEARLY MONTHLY WEEKLY DAILY HOURLY MINUTELY]
      expect(described_class::DAILY).to eq 'DAILY'
    end

    it 'derives DAYS_OF_WEEK from Date::DAYNAMES with named constants' do
      expect(described_class::DAYS_OF_WEEK).to eq %w[SU MO TU WE TH FR SA]
      expect(described_class::SUNDAY).to eq 'SU'
      expect(described_class::MONDAY).to eq 'MO'
    end

    it 'exposes MONTHLY_OPTIONS with prefixed named constants' do
      expect(described_class::MONTHLY_OPTIONS).to eq %w[DATE NTH_DAY]
      expect(described_class::MONTHLY_DATE).to eq 'DATE'
      expect(described_class::MONTHLY_NTH_DAY).to eq 'NTH_DAY'
    end
  end

  describe 'frequency predicates' do
    it 'returns true for the matching frequency' do
      described_class::FREQUENCIES.each_key do |frequency|
        recurrence = described_class.new(frequency:, interval: 1)
        expect(recurrence.public_send(:"#{frequency.downcase}?")).to be true
      end
    end

    it 'returns false for non-matching frequencies' do
      recurrence = described_class.new(frequency: 'DAILY', interval: 1)
      expect(recurrence).not_to be_yearly
      expect(recurrence).not_to be_monthly
      expect(recurrence).not_to be_weekly
      expect(recurrence).not_to be_hourly
      expect(recurrence).not_to be_minutely
    end
  end

  describe '#rrule' do
    subject do
      described_class.new(date_of_month:, day_of_month:, day_of_week:, frequency:, interval:, minute_of_hour:,
                          nth_day_of_month:).rrule
    end

    let(:date_of_month) { nil }
    let(:day_of_month) { nil }
    let(:day_of_week) { nil }
    let(:interval) { 10 }
    let(:minute_of_hour) { nil }
    let(:nth_day_of_month) { nil }

    context 'when frequency is yearly' do
      let(:frequency) { 'YEARLY' }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10' }
    end

    context 'when frequency is monthly' do
      let(:frequency) { 'MONTHLY' }

      context 'when there is not specific day of month' do
        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10' }
      end

      context 'when there is a specific day of the month' do
        let(:date_of_month) { 20 }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=20' }
      end

      context 'when there is an nth day of the month' do
        let(:day_of_month) { 'MO' }
        let(:nth_day_of_month) { -1 }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYDAY=MO;BYSETPOS=-1' }
      end
    end

    context 'when frequency is weekly' do
      let(:frequency) { 'WEEKLY' }

      context 'with set day_of_week' do
        let(:day_of_week) { 'MO' }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10;BYDAY=MO' }
      end

      context 'with a blank day_of_week' do
        let(:day_of_week) { ' ' }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10' }
      end
    end

    context 'when frequency is daily' do
      let(:frequency) { 'DAILY' }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10' }
    end

    context 'when frequency is hourly' do
      context 'with blank minute_of_hour' do
        let(:frequency) { 'HOURLY' }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10' }
      end

      context 'with set minute_of_hour' do
        let(:frequency) { 'HOURLY' }
        let(:minute_of_hour) { 30 }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10;BYMINUTE=30' }
      end
    end
  end

  describe '#from_rrule' do
    subject { described_class.from_rrule(rrule:) }

    cases = [
      ['FREQ=MINUTELY;INTERVAL=10',
       { frequency: 'MINUTELY', interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10',
       { frequency: 'HOURLY', interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10;BYMINUTE=30',
       { frequency: 'HOURLY', interval: 10, minute_of_hour: 30 }],
      ['FREQ=DAILY;INTERVAL=10',
       { frequency: 'DAILY', interval: 10 }],
      ['FREQ=YEARLY;INTERVAL=10',
       { frequency: 'YEARLY', interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10',
       { frequency: 'MONTHLY', interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=10',
       { frequency: 'MONTHLY', interval: 10, date_of_month: 10, monthly_option: 'DATE' }],
      ['FREQ=MONTHLY;INTERVAL=10;BYDAY=WE;BYSETPOS=-1',
       { frequency: 'MONTHLY', interval: 10, day_of_month: 'WE',
         nth_day_of_month: -1, monthly_option: 'NTH_DAY' }],
      ['FREQ=WEEKLY;INTERVAL=10;',
       { frequency: 'WEEKLY', interval: 10 }],
      ['FREQ=WEEKLY;INTERVAL=10;BYDAY=WE',
       { frequency: 'WEEKLY', interval: 10, day_of_week: 'WE' }]
    ].freeze

    recurrence_form_attrs = %i[date_of_month day_of_month day_of_week frequency interval monthly_option
                               nth_day_of_month]

    cases.each do |(rrule, expected_values)|
      context "when given #{rrule}" do
        let(:rrule) { rrule }

        it 'produces a valid recurrence object' do
          expect(subject).to be_valid
        end

        recurrence_form_attrs.each do |attr|
          it "initializes the #{attr} attr" do
            expect(subject.send(attr)).to eq expected_values[attr]
          end
        end
      end
    end

    it 'is not valid if BYMONTHDAY is > 28' do
      expect(described_class.from_rrule(rrule: 'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=29')).not_to be_valid
    end
  end

  describe '#nth_day_of_month=' do
    it 'coerces string values to integers' do
      recurrence = described_class.new
      recurrence.nth_day_of_month = '2'
      expect(recurrence.nth_day_of_month).to eq 2
    end

    it 'coerces negative string values to integers' do
      recurrence = described_class.new
      recurrence.nth_day_of_month = '-1'
      expect(recurrence.nth_day_of_month).to eq(-1)
    end

    it 'sets nil for nil input' do
      recurrence = described_class.new
      recurrence.nth_day_of_month = nil
      expect(recurrence.nth_day_of_month).to be_nil
    end

    it 'sets nil for empty string input' do
      recurrence = described_class.new
      recurrence.nth_day_of_month = ''
      expect(recurrence.nth_day_of_month).to be_nil
    end
  end

  describe 'Comparable comparator functions' do
    it 'compares frequencies scientifically' do
      smaller_frequency = described_class.new(frequency: 'YEARLY')
      larger_frequency = described_class.new(frequency: 'HOURLY')

      expect(smaller_frequency).to be < larger_frequency
      expect(larger_frequency).to be > smaller_frequency
      expect(larger_frequency.dup).to eq larger_frequency
    end

    it 'returns nil when compared to a non-Recurrence object' do
      recurrence = described_class.new(frequency: 'DAILY')
      expect(recurrence <=> 'not a recurrence').to be_nil
    end

    it 'returns 0 for equal frequencies' do
      a = described_class.new(frequency: 'WEEKLY', interval: 1)
      b = described_class.new(frequency: 'WEEKLY', interval: 5)
      expect(a <=> b).to eq 0
    end
  end
end
