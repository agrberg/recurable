# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define do
  create_table :events, force: true do |t|
    t.string :rrule
  end
end

class Event < ActiveRecord::Base
  include Recurable
end

RSpec.describe Recurable do
  subject(:event) { Event.new }

  describe 'serialize' do
    it 'defaults to a daily recurrence' do
      expect(event.rrule).to be_a(Recurrence)
      expect(event.rrule.frequency).to eq 'DAILY'
      expect(event.rrule.interval).to eq 1
    end

    it 'round-trips through the database' do
      event.rrule = Recurrence.new(frequency: 'WEEKLY', interval: 2, by_day: %w[MO WE FR])
      event.save!

      reloaded = Event.find(event.id)
      expect(reloaded.rrule).to be_a(Recurrence)
      expect(reloaded.rrule.frequency).to eq 'WEEKLY'
      expect(reloaded.rrule.interval).to eq 2
      expect(reloaded.rrule.by_day).to eq %w[MO WE FR]
    end

    it 'persists as an RRULE string' do
      event.rrule = Recurrence.new(frequency: 'MONTHLY', interval: 1, by_month_day: [15])
      event.save!

      raw = Event.connection.select_value("SELECT rrule FROM events WHERE id = #{event.id}")
      expect(raw).to eq 'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15'
    end

    it 'loads nil rrule as nil' do
      Event.connection.execute('INSERT INTO events (rrule) VALUES (NULL)')
      loaded = Event.last
      expect(loaded.rrule).to be_nil
    end
  end

  describe 'alias_attribute :recurrence' do
    it 'aliases rrule as recurrence' do
      event.rrule = Recurrence.new(frequency: 'DAILY', interval: 3)
      expect(event.recurrence).to eq event.rrule
    end
  end

  describe 'delegation' do
    it 'delegates attribute readers to rrule' do
      event.rrule = Recurrence.new(frequency: 'WEEKLY', interval: 2, by_day: ['TU'])
      expect(event.frequency).to eq 'WEEKLY'
      expect(event.interval).to eq 2
      expect(event.by_day).to eq ['TU']
    end

    it 'delegates attribute writers to rrule' do
      event.frequency = 'MONTHLY'
      event.interval = 3
      event.by_month_day = [10]
      expect(event.rrule.frequency).to eq 'MONTHLY'
      expect(event.rrule.interval).to eq 3
      expect(event.rrule.by_month_day).to eq [10]
    end

    it 'delegates frequency predicates' do
      event.frequency = 'WEEKLY'
      expect(event).to be_weekly
      expect(event).not_to be_daily
      expect(event).not_to be_monthly
    end
  end

  describe 'validations' do
    it 'is valid with default attributes' do
      expect(event).to be_valid
    end

    it 'validates frequency presence' do
      event.frequency = nil
      expect(event).not_to be_valid
      expect(event.errors[:frequency]).to include("can't be blank")
    end

    it 'validates frequency inclusion' do
      event.frequency = 'SECONDLY'
      expect(event).not_to be_valid
      expect(event.errors[:frequency]).to include('is not included in the list')
    end

    it 'validates interval presence' do
      event.interval = nil
      expect(event).not_to be_valid
      expect(event.errors[:interval]).to include("can't be blank")
    end

    it 'validates interval is a positive integer' do
      event.interval = 0
      expect(event).not_to be_valid
      expect(event.errors[:interval]).to include('must be greater than 0')
    end

    it 'validates by_day values' do
      event.frequency = 'WEEKLY'
      event.by_day = ['MONDAY']
      expect(event).not_to be_valid
      expect(event.errors[:by_day].first).to include('invalid value')
    end

    it 'validates count is a positive integer' do
      event.count = -1
      expect(event).not_to be_valid
      expect(event.errors[:count]).to include('must be greater than 0')
    end

    it 'validates count and until are mutually exclusive' do
      event.count = 5
      event.repeat_until = Time.utc(2026, 12, 31)
      expect(event).not_to be_valid
      expect(event.errors[:base]).to include('COUNT and UNTIL are mutually exclusive')
    end

    it 'allows count without until' do
      event.count = 10
      expect(event).to be_valid
    end

    it 'allows until without count' do
      event.repeat_until = Time.utc(2026, 12, 31)
      expect(event).to be_valid
    end
  end

  describe RruleUtils do
    it 'is included and provides humanize_recurrence' do
      event.frequency = 'DAILY'
      event.interval = 1
      expect(event.humanize_recurrence).to eq 'every day'
    end
  end
end
