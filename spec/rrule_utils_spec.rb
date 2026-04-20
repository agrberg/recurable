# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RruleUtils do
  def build_model(rrule_str)
    Struct.new(:recurrence).new(Recurrence.from_rrule(rrule_str)).extend(described_class)
  end

  describe '#recurrence_times' do
    context 'with DST transitions (America/New_York)' do
      around { |test| Time.use_zone('America/New_York', &test) }

      it 'produces a months worth of days across spring-forward' do
        model = build_model('FREQ=DAILY;INTERVAL=1')
        dt_start_at = Time.zone.local(2023, 3, 1)

        times = model.recurrence_times(project_from: dt_start_at.beginning_of_month,
                                       project_to: dt_start_at.end_of_month,
                                       dt_start_at:)

        expect(times).to eq(1.upto(31).map { Time.zone.local(2023, 3, _1) })
      end

      it 'produces 23 unique hours on spring-forward day (2am does not exist)' do
        model = build_model('FREQ=HOURLY;INTERVAL=1')
        spring_ahead = Time.zone.local(2023, 3, 12)

        times = model.recurrence_times(project_from: spring_ahead.beginning_of_day,
                                       project_to: spring_ahead.end_of_day,
                                       dt_start_at: Time.zone.local(2023, 3, 1))

        # 2am doesn't exist on spring-forward day; Time.zone.local shifts it to 3am, creating a duplicate
        expect(times).to eq((0..23).map { Time.zone.local(2023, 3, 12, _1) }.uniq)
      end

      it 'produces a months worth of days across fall-back' do
        model = build_model('FREQ=DAILY;INTERVAL=1')
        dt_start_at = Time.zone.local(2023, 11, 1)

        times = model.recurrence_times(project_from: dt_start_at.beginning_of_month,
                                       project_to: dt_start_at.end_of_month,
                                       dt_start_at:)

        expect(times).to eq(1.upto(30).map { Time.zone.local(2023, 11, _1) })
      end

      it 'produces a days worth of hours not doubling 1am on fall-back' do
        model = build_model('FREQ=HOURLY;INTERVAL=1')
        fall_back = Time.zone.local(2023, 11, 5)

        times = model.recurrence_times(project_from: fall_back.beginning_of_day,
                                       project_to: fall_back.end_of_day,
                                       dt_start_at: Time.zone.local(2023, 11, 1))

        expect(times).to eq((0..23).map { Time.zone.local(2023, 11, 5, _1) })
      end

      it 'produces 24 hours on a winter day (no DST transition)' do
        model = build_model('FREQ=HOURLY;INTERVAL=1')
        dt_start_at = Time.zone.local(2023, 1, 15)

        times = model.recurrence_times(project_from: dt_start_at.beginning_of_day,
                                       project_to: dt_start_at.end_of_day,
                                       dt_start_at:)

        expect(times).to eq((0..23).map { Time.zone.local(2023, 1, 15, _1) })
      end

      it 'produces 24 hours on a summer day (no DST transition)' do
        model = build_model('FREQ=HOURLY;INTERVAL=1')
        dt_start_at = Time.zone.local(2023, 7, 15)

        times = model.recurrence_times(project_from: dt_start_at.beginning_of_day,
                                       project_to: dt_start_at.end_of_day,
                                       dt_start_at:)

        expect(times).to eq((0..23).map { Time.zone.local(2023, 7, 15, _1) })
      end
    end

    context 'with dt_start_at' do
      around { |test| Time.use_zone('America/Chicago', &test) }

      it 'offsets occurrences from dt_start_at when given' do
        model = build_model('FREQ=DAILY;INTERVAL=1')

        times = model.recurrence_times(project_from: Time.zone.local(2023, 1, 1, 12, 0),
                                       project_to: Time.zone.local(2023, 1, 2, 12, 0),
                                       dt_start_at: Time.zone.local(2023, 1, 1, 11, 0))

        expect(times).to eq [Time.zone.local(2023, 1, 2, 11, 0)]
      end

      it 'defaults to project_from if not passed' do
        model = build_model('FREQ=DAILY;INTERVAL=1')

        times = model.recurrence_times(project_from: Time.zone.local(2023, 1, 1, 12, 0),
                                       project_to: Time.zone.local(2023, 1, 2, 12, 0))

        expect(times).to eq [Time.zone.local(2023, 1, 1, 12, 0), Time.zone.local(2023, 1, 2, 12, 0)]
      end
    end
  end

  describe '#last_recurrence_time_before' do
    around { |test| Time.use_zone('America/Chicago', &test) }

    it 'finds the last yearly recurrence' do
      model = build_model('FREQ=YEARLY;INTERVAL=3')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2022-01-01')
    end

    it 'finds the last monthly recurrence' do
      model = build_model('FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=21')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2022-10-21')
    end

    it 'finds the last weekly recurrence' do
      model = build_model('FREQ=WEEKLY;INTERVAL=10;BYDAY=TU')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2022-11-01')
    end

    it 'finds the last daily recurrence' do
      model = build_model('FREQ=DAILY;INTERVAL=23')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2022-12-01')))
        .to eq Time.zone.parse('2022-12-24')
    end

    it 'finds the last hourly recurrence' do
      model = build_model('FREQ=HOURLY;INTERVAL=23')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2022-12-31')))
        .to eq Time.zone.parse('2022-12-31 23:00:00')
    end

    it 'finds the last minutely recurrence' do
      model = build_model('FREQ=MINUTELY;INTERVAL=46')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2022-12-31 23:00:00')))
        .to eq Time.zone.parse('2022-12-31 23:46:00')
    end

    it 'returns nil when dt_start_at is after the boundary' do
      model = build_model('FREQ=YEARLY;INTERVAL=1')
      expect(model.last_recurrence_time_before(Time.zone.parse('2022-12-31 23:59:59'),
                                               dt_start_at: Time.zone.parse('2023-01-01')))
        .to be_nil
    end
  end

  describe '#next_recurrence_time_after' do
    around { |test| Time.use_zone('America/Chicago', &test) }

    it 'finds the next yearly recurrence' do
      model = build_model('FREQ=YEARLY;INTERVAL=3')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2025-01-01')
    end

    it 'finds the next monthly recurrence' do
      model = build_model('FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=21')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2023-01-21')
    end

    it 'finds the next weekly recurrence' do
      model = build_model('FREQ=WEEKLY;INTERVAL=10;BYDAY=TU')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2019-01-01')))
        .to eq Time.zone.parse('2023-01-10')
    end

    it 'finds the next daily recurrence' do
      model = build_model('FREQ=DAILY;INTERVAL=23')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2022-12-01')))
        .to eq Time.zone.parse('2023-01-16')
    end

    it 'finds the next hourly recurrence' do
      model = build_model('FREQ=HOURLY;INTERVAL=23')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2022-12-31 23:00:00')))
        .to eq Time.zone.parse('2023-01-01 22:00:00')
    end

    it 'finds the next minutely recurrence' do
      model = build_model('FREQ=MINUTELY;INTERVAL=46')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-12-31 23:59:59'),
                                              dt_start_at: Time.zone.parse('2022-12-31 23:00:00')))
        .to eq Time.zone.parse('2023-01-01 00:32:00')
    end

    it 'returns the first recurrence when dt_start_at is after the boundary' do
      model = build_model('FREQ=YEARLY;INTERVAL=1')
      expect(model.next_recurrence_time_after(Time.zone.parse('2022-06-15'),
                                              dt_start_at: Time.zone.parse('2023-01-01')))
        .to eq Time.zone.parse('2023-01-01')
    end
  end

  describe '#humanize_recurrence' do
    it 'delegates to RRule::Rule#humanize' do # rubocop:disable RSpec/MultipleExpectations -- just a simple sampling
      expect(build_model('FREQ=DAILY;INTERVAL=1').humanize_recurrence).to eq 'every day'
      expect(build_model('FREQ=DAILY;INTERVAL=3').humanize_recurrence).to eq 'every 3 days'
      expect(build_model('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO').humanize_recurrence).to eq 'every 2 weeks on Monday'
      expect(build_model('FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15').humanize_recurrence).to eq 'every month on the 15th'
      expect(build_model('FREQ=HOURLY;INTERVAL=1').humanize_recurrence).to eq 'every hour'
      expect(build_model('FREQ=HOURLY;INTERVAL=4').humanize_recurrence).to eq 'every 4 hours'
      expect(build_model('FREQ=MINUTELY;INTERVAL=1').humanize_recurrence).to eq 'every minute'
      expect(build_model('FREQ=MINUTELY;INTERVAL=30').humanize_recurrence).to eq 'every 30 minutes'
    end
  end
end
