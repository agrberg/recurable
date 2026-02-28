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
end
