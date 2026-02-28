# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recurrence do
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
      let(:frequency) { described_class::Frequencies::YEARLY }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10' }
    end

    context 'when frequency is monthly' do
      let(:frequency) { described_class::Frequencies::MONTHLY }

      context 'when there is not specific day of month' do
        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10' }
      end

      context 'when there is a specific day of the month' do
        let(:date_of_month) { 20 }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=20' }
      end

      context 'when there is an nth day of the month' do
        let(:day_of_month) { described_class::ByDayValues::MONDAY }
        let(:nth_day_of_month) { -1 }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYDAY=MO;BYSETPOS=-1' }
      end
    end

    context 'when frequency is weekly' do
      let(:frequency) { described_class::Frequencies::WEEKLY }

      context 'with set day_of_week' do
        let(:day_of_week) { described_class::ByDayValues::MONDAY }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10;BYDAY=MO' }
      end

      context 'with a blank day_of_week' do
        let(:day_of_week) { ' ' }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10' }
      end
    end

    context 'when frequency is daily' do
      let(:frequency) { described_class::Frequencies::DAILY }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10' }
    end

    context 'when frequency is hourly' do
      context 'with blank minute_of_hour' do
        let(:frequency) { described_class::Frequencies::HOURLY }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10' }
      end

      context 'with set minute_of_hour' do
        let(:frequency) { described_class::Frequencies::HOURLY }
        let(:minute_of_hour) { 30 }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10;BYMINUTE=30' }
      end
    end
  end

  describe '#with_defaults' do
    subject { described_class.with_defaults }

    it 'has its default values for everything' do
      expect(subject.rrule).to eq 'FREQ=DAILY;INTERVAL=1'
      expect(subject.recurrence_statement).to eq 'Repeats every 1 day.'
      expect(subject.frequency).to eq 'DAILY'
      expect(subject.interval).to eq 1
      expect(subject.day_of_week).to be_nil
    end
  end

  describe '#from_rrule' do
    subject { described_class.from_rrule(rrule:) }

    cases = [
      ['FREQ=MINUTELY;INTERVAL=10',
       { frequency: described_class::Frequencies::MINUTELY, interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10',
       { frequency: described_class::Frequencies::HOURLY, interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10;BYMINUTE=30',
       { frequency: described_class::Frequencies::HOURLY, interval: 10, minute_of_hour: 30 }],
      ['FREQ=DAILY;INTERVAL=10',
       { frequency: described_class::Frequencies::DAILY, interval: 10 }],
      ['FREQ=YEARLY;INTERVAL=10',
       { frequency: described_class::Frequencies::YEARLY, interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10',
       { frequency: described_class::Frequencies::MONTHLY, interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=10',
       { frequency: described_class::Frequencies::MONTHLY, interval: 10, date_of_month: 10,
         monthly_option: described_class::MonthlyOptions::DATE }],
      ['FREQ=MONTHLY;INTERVAL=10;BYDAY=WE;BYSETPOS=-1',
       { frequency: described_class::Frequencies::MONTHLY, interval: 10,
         day_of_month: described_class::ByDayValues::WEDNESDAY,
         nth_day_of_month: -1, monthly_option: described_class::MonthlyOptions::NTH_DAY }],
      ['FREQ=WEEKLY;INTERVAL=10;',
       { frequency: described_class::Frequencies::WEEKLY, interval: 10 }],
      ['FREQ=WEEKLY;INTERVAL=10;BYDAY=WE',
       { frequency: described_class::Frequencies::WEEKLY, interval: 10,
         day_of_week: described_class::ByDayValues::WEDNESDAY }]
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
      smaller_frequency = described_class.new(frequency: Recurrence::Frequencies::YEARLY)
      larger_frequency = described_class.new(frequency: Recurrence::Frequencies::HOURLY)

      expect(smaller_frequency).to be < larger_frequency
      expect(larger_frequency).to be > smaller_frequency
      expect(larger_frequency.dup).to eq larger_frequency
    end

    it 'returns nil when compared to a non-Recurrence object' do
      recurrence = described_class.new(frequency: Recurrence::Frequencies::DAILY)
      expect(recurrence <=> 'not a recurrence').to be_nil
    end

    it 'returns 0 for equal frequencies' do
      a = described_class.new(frequency: Recurrence::Frequencies::WEEKLY, interval: 1)
      b = described_class.new(frequency: Recurrence::Frequencies::WEEKLY, interval: 5)
      expect(a <=> b).to eq 0
    end
  end

  describe '#last_recurrence_time_before' do
    subject(:last_recurrence_time) do
      described_class.from_rrule(rrule:).last_recurrence_time_before(dt_start_at:, end_at:)
    end

    let(:dt_start_at) { Time.zone.parse('2019-01-01 00:00:00') }
    let(:end_at) { Time.zone.parse('2022-12-31 23:59:59') }

    around { |test| Time.use_zone('America/Chicago', &test) }

    context 'with yearly frequencies' do
      let(:rrule) { 'FREQ=YEARLY;INTERVAL=3' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-01-01 00:00:00')
      end
    end

    context 'with monthly frequencies' do
      let(:rrule) { 'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=21' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-10-21 00:00:00')
      end
    end

    context 'with weekly frequencies' do
      let(:rrule) { 'FREQ=WEEKLY;INTERVAL=10;BYDAY=TU' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-11-01 00:00:00')
      end
    end

    context 'with daily frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-01 00:00:00') }
      let(:rrule) { 'FREQ=DAILY;INTERVAL=23' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-12-24 00:00:00')
      end
    end

    context 'with hourly frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-31 00:00:00') }
      let(:rrule) { 'FREQ=HOURLY;INTERVAL=23' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-12-31 23:00:00')
      end
    end

    context 'with minutely frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-31 23:00:00') }
      let(:rrule) { 'FREQ=MINUTELY;INTERVAL=46' }

      it 'returns the last recurrence time before the end date' do
        expect(last_recurrence_time).to eq Time.zone.parse('2022-12-31 23:46:00')
      end
    end

    context 'when the start date after the recurrence period so there are no previous recurrences' do
      let(:dt_start_at) { Time.zone.parse('2023-01-01 00:00:00') }
      let(:end_at) { Time.zone.parse('2022-12-31 23:59:59') }
      let(:rrule) { 'FREQ=YEARLY;INTERVAL=1' }

      it 'returns `nil`' do
        expect(last_recurrence_time).to be_nil
      end
    end
  end

  describe '#recurrence_times' do
    it 'correctly generates recurrences given a dt_start_at' do
      Time.use_zone('America/Chicago') do
        dt_start_at = Time.zone.local(2023, 1, 1, 11, 0)
        project_from = Time.zone.local(2023, 1, 1, 12, 0) # Too late to generate recurrence on its day
        project_to = Time.zone.local(2023, 1, 2, 12, 0) # Late enough to generate a recurrence on its day

        expect(
          described_class.from_rrule(rrule: 'FREQ=DAILY;INTERVAL=1').recurrence_times(project_from:, project_to:,
                                                                                      dt_start_at:)
        ).to eq [Time.zone.local(2023, 1, 2, 11, 0)]
      end
    end

    it 'uses project_from as dt_start_at if not passed' do
      Time.use_zone('America/Chicago') do
        project_from = Time.zone.local(2023, 1, 1, 12, 0) # Too late to generate recurrence on its day
        project_to = Time.zone.local(2023, 1, 2, 12, 0) # Late enough to generate a recurrence on its day

        expect(
          described_class.from_rrule(rrule: 'FREQ=DAILY;INTERVAL=1').recurrence_times(project_from:, project_to:)
        ).to eq [Time.zone.local(2023, 1, 1, 12, 0), Time.zone.local(2023, 1, 2, 12, 0)]
      end
    end
  end
end
