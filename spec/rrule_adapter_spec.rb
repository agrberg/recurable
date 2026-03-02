# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RruleAdapter do
  describe '#times_between' do
    around { |test| Time.use_zone(tzid, &test) }

    let(:daily_recurrence) { Recurrence.from_rrule(rrule: 'FREQ=DAILY;INTERVAL=1') }
    let(:hourly_recurrence) { Recurrence.from_rrule(rrule: 'FREQ=HOURLY;INTERVAL=1') }
    let(:tzid) { 'America/New_York' }

    context 'when moving from ST => DST' do
      let(:dt_start_at) { Time.zone.local(2023, 3, 1) }

      it 'produces a months worth of days' do
        times_produced = described_class.new(daily_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: dt_start_at.beginning_of_month,
                                                       project_to: dt_start_at.end_of_month)
        times_expected = 1.upto(31).map { Time.zone.local(2023, 3, _1) }

        expect(times_produced).to eq(times_expected)
      end

      # On spring-forward day (2023-03-12 in ET), 2:00 AM doesn't exist — clocks jump
      # from 1:59 AM EST to 3:00 AM EDT. The adapter's DST adjustment maps both the
      # would-be 2:00 AM and 3:00 AM to the same wall-clock time (3:00 AM EDT), then
      # deduplicates via `.uniq`, producing 23 unique hours instead of 24.
      it 'produces 23 unique hours on spring-forward day (2am does not exist)' do
        spring_ahead = Time.zone.local(2023, 3, 12)
        times_produced = described_class.new(hourly_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: spring_ahead.beginning_of_day,
                                                       project_to: spring_ahead.end_of_day)
        times_expected = (0..23).without(3).map { Time.zone.local(2023, 3, 12, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when moving from DST => ST' do
      let(:dt_start_at) { Time.zone.local(2023, 11, 1) }

      it 'produces a months worth of days' do
        times_produced = described_class.new(daily_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: dt_start_at.beginning_of_month,
                                                       project_to: dt_start_at.end_of_month)
        times_expected = 1.upto(30).map { Time.zone.local(2023, 11, _1) }

        expect(times_produced).to eq(times_expected)
      end

      it 'produces a days worth of hours not doubling 1am' do
        fall_back = Time.zone.local(2023, 11, 5)
        times_produced = described_class.new(hourly_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: fall_back.beginning_of_day,
                                                       project_to: fall_back.end_of_day)
        times_expected = (0..23).map { Time.zone.local(2023, 11, 5, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when entirely within standard time (no DST transition)' do
      let(:dt_start_at) { Time.zone.local(2023, 1, 15) }

      it 'produces 24 hours on a winter day' do
        times_produced = described_class.new(hourly_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: dt_start_at.beginning_of_day,
                                                       project_to: dt_start_at.end_of_day)
        times_expected = (0..23).map { Time.zone.local(2023, 1, 15, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end

    context 'when entirely within daylight time (no DST transition)' do
      let(:dt_start_at) { Time.zone.local(2023, 7, 15) }

      it 'produces 24 hours on a summer day' do
        times_produced = described_class.new(hourly_recurrence, dt_start_at:, tzid:)
                                        .times_between(project_from: dt_start_at.beginning_of_day,
                                                       project_to: dt_start_at.end_of_day)
        times_expected = (0..23).map { Time.zone.local(2023, 7, 15, _1) }

        expect(times_produced).to eq(times_expected)
      end
    end
  end

  describe '.times_between' do
    it 'correctly generates recurrences given a dt_start_at' do
      Time.use_zone('America/Chicago') do
        recurrence = Recurrence.from_rrule(rrule: 'FREQ=DAILY;INTERVAL=1')
        dt_start_at = Time.zone.local(2023, 1, 1, 11, 0)
        project_from = Time.zone.local(2023, 1, 1, 12, 0) # Too late to generate recurrence on its day
        project_to = Time.zone.local(2023, 1, 2, 12, 0) # Late enough to generate a recurrence on its day

        expect(
          described_class.times_between(recurrence, project_from:, project_to:, dt_start_at:)
        ).to eq [Time.zone.local(2023, 1, 2, 11, 0)]
      end
    end

    it 'uses project_from as dt_start_at if not passed' do
      Time.use_zone('America/Chicago') do
        recurrence = Recurrence.from_rrule(rrule: 'FREQ=DAILY;INTERVAL=1')
        project_from = Time.zone.local(2023, 1, 1, 12, 0) # Too late to generate recurrence on its day
        project_to = Time.zone.local(2023, 1, 2, 12, 0) # Late enough to generate a recurrence on its day

        expect(
          described_class.times_between(recurrence, project_from:, project_to:)
        ).to eq [Time.zone.local(2023, 1, 1, 12, 0), Time.zone.local(2023, 1, 2, 12, 0)]
      end
    end
  end

  describe '.last_time_before' do
    subject(:last_recurrence_time) do
      recurrence = Recurrence.from_rrule(rrule:)
      described_class.last_time_before(recurrence, dt_start_at:, end_at:)
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
end
