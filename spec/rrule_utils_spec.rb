# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RruleUtils do
  subject(:model) { Struct.new(:recurrence).new(recurrence).extend(described_class) }

  describe '#recurrence_times DST handling' do
    around { |test| Time.use_zone('America/New_York', &test) }

    let(:daily_recurrence) { Recurrence.from_rrule('FREQ=DAILY;INTERVAL=1') }
    let(:hourly_recurrence) { Recurrence.from_rrule('FREQ=HOURLY;INTERVAL=1') }

    context 'when moving from ST => DST' do
      let(:dt_start_at) { Time.zone.local(2023, 3, 1) }

      it 'produces a months worth of days' do
        model = Struct.new(:recurrence).new(daily_recurrence).extend(described_class)
        times_produced = model.recurrence_times(project_from: dt_start_at.beginning_of_month,
                                                project_to: dt_start_at.end_of_month,
                                                dt_start_at:)
        times_expected = 1.upto(31).map { Time.zone.local(2023, 3, _1) }

        expect(times_produced).to eq(times_expected)
      end

      it 'produces 23 unique hours on spring-forward day (2am does not exist)' do
        model = Struct.new(:recurrence).new(hourly_recurrence).extend(described_class)
        spring_ahead = Time.zone.local(2023, 3, 12)
        times_produced = model.recurrence_times(project_from: spring_ahead.beginning_of_day,
                                                project_to: spring_ahead.end_of_day,
                                                dt_start_at:)
        times_expected = (0..23).without(3).map { Time.zone.local(2023, 3, 12, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when moving from DST => ST' do
      let(:dt_start_at) { Time.zone.local(2023, 11, 1) }

      it 'produces a months worth of days' do
        model = Struct.new(:recurrence).new(daily_recurrence).extend(described_class)
        times_produced = model.recurrence_times(project_from: dt_start_at.beginning_of_month,
                                                project_to: dt_start_at.end_of_month,
                                                dt_start_at:)
        times_expected = 1.upto(30).map { Time.zone.local(2023, 11, _1) }

        expect(times_produced).to eq(times_expected)
      end

      it 'produces a days worth of hours not doubling 1am' do
        model = Struct.new(:recurrence).new(hourly_recurrence).extend(described_class)
        fall_back = Time.zone.local(2023, 11, 5)
        times_produced = model.recurrence_times(project_from: fall_back.beginning_of_day,
                                                project_to: fall_back.end_of_day,
                                                dt_start_at:)
        times_expected = (0..23).map { Time.zone.local(2023, 11, 5, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when entirely within standard time (no DST transition)' do
      let(:dt_start_at) { Time.zone.local(2023, 1, 15) }

      it 'produces 24 hours on a winter day' do
        model = Struct.new(:recurrence).new(hourly_recurrence).extend(described_class)
        times_produced = model.recurrence_times(project_from: dt_start_at.beginning_of_day,
                                                project_to: dt_start_at.end_of_day,
                                                dt_start_at:)
        times_expected = (0..23).map { Time.zone.local(2023, 1, 15, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when entirely within daylight time (no DST transition)' do
      let(:dt_start_at) { Time.zone.local(2023, 7, 15) }

      it 'produces 24 hours on a summer day' do
        model = Struct.new(:recurrence).new(hourly_recurrence).extend(described_class)
        times_produced = model.recurrence_times(project_from: dt_start_at.beginning_of_day,
                                                project_to: dt_start_at.end_of_day,
                                                dt_start_at:)
        times_expected = (0..23).map { Time.zone.local(2023, 7, 15, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end
  end

  describe '#recurrence_times' do
    it 'correctly generates recurrences given a dt_start_at' do
      Time.use_zone('America/Chicago') do
        recurrence = Recurrence.from_rrule('FREQ=DAILY;INTERVAL=1')
        model = Struct.new(:recurrence).new(recurrence).extend(described_class)
        dt_start_at = Time.zone.local(2023, 1, 1, 11, 0)
        project_from = Time.zone.local(2023, 1, 1, 12, 0)
        project_to = Time.zone.local(2023, 1, 2, 12, 0)

        expect(
          model.recurrence_times(project_from:, project_to:, dt_start_at:)
        ).to eq [Time.zone.local(2023, 1, 2, 11, 0)]
      end
    end

    it 'uses project_from as dt_start_at if not passed' do
      Time.use_zone('America/Chicago') do
        recurrence = Recurrence.from_rrule('FREQ=DAILY;INTERVAL=1')
        model = Struct.new(:recurrence).new(recurrence).extend(described_class)
        project_from = Time.zone.local(2023, 1, 1, 12, 0)
        project_to = Time.zone.local(2023, 1, 2, 12, 0)

        expect(
          model.recurrence_times(project_from:, project_to:)
        ).to eq [Time.zone.local(2023, 1, 1, 12, 0), Time.zone.local(2023, 1, 2, 12, 0)]
      end
    end
  end

  describe '#last_recurrence_time_before' do
    subject(:last_recurrence_time) { model.last_recurrence_time_before(end_at, dt_start_at:) }

    let(:recurrence) { Recurrence.from_rrule(rrule) }
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

  describe '#next_recurrence_time_after' do
    subject(:next_recurrence_time) { model.next_recurrence_time_after(after, dt_start_at:) }

    let(:recurrence) { Recurrence.from_rrule(rrule) }
    let(:dt_start_at) { Time.zone.parse('2019-01-01 00:00:00') }
    let(:after) { Time.zone.parse('2022-12-31 23:59:59') }

    around { |test| Time.use_zone('America/Chicago', &test) }

    context 'with yearly frequencies' do
      let(:rrule) { 'FREQ=YEARLY;INTERVAL=3' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2025-01-01 00:00:00')
      end
    end

    context 'with monthly frequencies' do
      let(:rrule) { 'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=21' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-21 00:00:00')
      end
    end

    context 'with weekly frequencies' do
      let(:rrule) { 'FREQ=WEEKLY;INTERVAL=10;BYDAY=TU' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-10 00:00:00')
      end
    end

    context 'with daily frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-01 00:00:00') }
      let(:rrule) { 'FREQ=DAILY;INTERVAL=23' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-16 00:00:00')
      end
    end

    context 'with hourly frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-31 23:00:00') }
      let(:rrule) { 'FREQ=HOURLY;INTERVAL=23' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-01 22:00:00')
      end
    end

    context 'with minutely frequencies' do
      let(:dt_start_at) { Time.zone.parse('2022-12-31 23:00:00') }
      let(:rrule) { 'FREQ=MINUTELY;INTERVAL=46' }

      it 'returns the next recurrence time after the given date' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-01 00:32:00')
      end
    end

    context 'when the start date is after the given date so there are no future recurrences' do
      let(:dt_start_at) { Time.zone.parse('2023-01-01 00:00:00') }
      let(:after) { Time.zone.parse('2022-06-15 00:00:00') }
      let(:rrule) { 'FREQ=YEARLY;INTERVAL=1' }

      it 'returns the first recurrence' do
        expect(next_recurrence_time).to eq Time.zone.parse('2023-01-01 00:00:00')
      end
    end
  end

  describe '#humanize_recurrence' do
    def build_model(rrule_str)
      Struct.new(:recurrence).new(Recurrence.from_rrule(rrule_str)).extend(described_class)
    end

    it 'delegates daily+ to RRule::Rule#humanize' do
      expect(build_model('FREQ=DAILY;INTERVAL=1').humanize_recurrence).to eq 'every day'
      expect(build_model('FREQ=DAILY;INTERVAL=3').humanize_recurrence).to eq 'every 3 days'
      expect(build_model('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO').humanize_recurrence).to include('week')
      expect(build_model('FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15').humanize_recurrence).to include('month')
    end

    it 'falls back to a simple string for hourly' do
      expect(build_model('FREQ=HOURLY;INTERVAL=1').humanize_recurrence).to eq 'every hour'
      expect(build_model('FREQ=HOURLY;INTERVAL=4').humanize_recurrence).to eq 'every 4 hours'
    end

    it 'falls back to a simple string for minutely' do
      expect(build_model('FREQ=MINUTELY;INTERVAL=1').humanize_recurrence).to eq 'every minute'
      expect(build_model('FREQ=MINUTELY;INTERVAL=30').humanize_recurrence).to eq 'every 30 minutes'
    end
  end
end
