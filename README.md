# Recurable

iCal RRULE recurrence library for Ruby with optional Rails/ActiveRecord integration. Full [RFC 5545](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) RRULE support.

## Quick Start: Standalone

No Rails required. Just ActiveModel and ActiveSupport.

```ruby
require 'recurable/recurrence'

# Build a recurrence from attributes
recurrence = Recurrence.new(frequency: 'DAILY', interval: 1)
recurrence.to_rrule   # => "FREQ=DAILY;INTERVAL=1"

# Parse an existing RRULE string
recurrence = Recurrence.from_rrule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR')
recurrence.frequency  # => "WEEKLY"
recurrence.interval   # => 2
recurrence.by_day     # => ["MO", "WE", "FR"]

# Frequency predicates
recurrence.weekly?    # => true
recurrence.daily?     # => false

# Frequency comparison (YEARLY < MONTHLY < ... < MINUTELY)
yearly  = Recurrence.new(frequency: 'YEARLY')
monthly = Recurrence.new(frequency: 'MONTHLY')
yearly < monthly      # => true
```

## Quick Start: With Rails

Add the gem, then prepend the `Recurable` concern on any model with an `rrule` string column:

```ruby
class Plan < ApplicationRecord
  include Recurable
end

plan = Plan.new
plan.frequency = 'MONTHLY'
plan.interval = 3
plan.by_month_day = [15]
plan.rrule                    # => #<Recurrence> with to_rrule "FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=15"
plan.valid?                   # validates both the model and the recurrence
plan.monthly?                 # => true
plan.humanize_recurrence      # => "every 3 months on the 15th"

# Time projection
plan.recurrence_times(
  project_from: Time.zone.local(2026, 1, 1),
  project_to:   Time.zone.local(2026, 7, 1)
)

# Boundary queries
plan.last_recurrence_time_before(Time.zone.now, dt_start_at: plan.created_at)
plan.next_recurrence_time_after(Time.zone.now, dt_start_at: plan.created_at)
```

## Installation

**Standalone** (no Rails):

```ruby
gem 'recurable'

# Then in your code:
require 'recurable/recurrence'
```

**With Rails**:

```ruby
gem 'recurable'

# Then in your code:
require 'recurable'
```

Requires ActiveRecord >= 7.1 for `serialize` with `default:` keyword support.

## Recurrence Attributes

`Recurrence` is a pure Ruby data class with named attributes mapping to [RFC 5545 RRULE components](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10):

| Attribute | Type | RRULE Component | Example | Description |
|-----------|------|-----------------|---------|-------------|
| `frequency` | String | `FREQ` | `"MONTHLY"` | Every month |
| `interval` | Integer | `INTERVAL` | `3` | Every 3rd frequency period |
| `by_day` | Array\<String\> | `BYDAY` | `["+2MO"]` | The second Monday |
| `by_day` | | | `["MO", "WE", "FR"]` | Monday, Wednesday, and Friday |
| `by_month_day` | Array\<Integer\> | `BYMONTHDAY` | `[1, 15]` | The 1st and 15th of the month |
| `by_set_pos` | Array\<Integer\> | `BYSETPOS` | `[-1]` | The last occurrence in the set |
| `count` | Integer | `COUNT` | `10` | Stop after 10 occurrences |
| `repeat_until` | Time (UTC) | `UNTIL` | `Time.utc(2026, 12, 31)` | Stop after December 31, 2026 |
| `hour_of_day` | Array\<Integer\> | `BYHOUR` | `[9, 17]` | At 9 AM and 5 PM |
| `minute_of_hour` | Array\<Integer\> | `BYMINUTE` | `[0, 30]` | At :00 and :30 past the hour |
| `second_of_minute` | Array\<Integer\> | `BYSECOND` | `[0, 30]` | At :00 and :30 past the minute |
| `month_of_year` | Array\<Integer\> | `BYMONTH` | `[1, 6]` | In January and June |
| `day_of_year` | Array\<Integer\> | `BYYEARDAY` | `[1, -1]` | First and last day of the year |
| `week_of_year` | Array\<Integer\> | `BYWEEKNO` | `[1, 52]` | Weeks 1 and 52 |
| `week_start` | String | `WKST` | `"MO"` | Weeks start on Monday |

All array attributes accept scalars (auto-wrapped) or arrays. `nil` and `[]` are normalized to `nil`.

```ruby
recurrence = Recurrence.new
recurrence.by_day = 'MO'       # => stored as ["MO"]
recurrence.by_day = %w[MO FR]  # => stored as ["MO", "FR"]
recurrence.by_day = []          # => stored as nil
```

### Monthly Recurrence Options

Monthly recurrences support two modes, determined by which attributes are set:

```ruby
# By date: "the 15th of every month"
Recurrence.new(frequency: 'MONTHLY', interval: 1, by_month_day: [15])
  .monthly_option         # => "DATE"

# By nth weekday: "the last Friday of every month"
Recurrence.new(frequency: 'MONTHLY', interval: 1, by_day: ['FR'], by_set_pos: [-1])
  .monthly_option         # => "NTH_DAY"
```

### RRULE Generation & Parsing

```ruby
# Generate: attributes → RRULE string
recurrence = Recurrence.new(frequency: 'MONTHLY', interval: 1, by_day: ['FR'], by_set_pos: [-1])
recurrence.to_rrule  # => "FREQ=MONTHLY;INTERVAL=1;BYDAY=FR;BYSETPOS=-1"

# Parse: RRULE string → Recurrence
parsed = Recurrence.from_rrule('FREQ=MONTHLY;INTERVAL=1;BYDAY=FR;BYSETPOS=-1')
parsed.by_day        # => ["FR"]
parsed.by_set_pos    # => [-1]

# Round-trip
parsed.to_rrule == recurrence.to_rrule  # => true
```

### COUNT and UNTIL

`COUNT` and `UNTIL` are mutually exclusive per RFC 5545. The `Recurable` concern validates this:

```ruby
# Limit by count
Recurrence.new(frequency: 'DAILY', interval: 1, count: 10)
  .to_rrule  # => "FREQ=DAILY;INTERVAL=1;COUNT=10"

# Limit by end date (stored as UTC)
Recurrence.new(frequency: 'DAILY', interval: 1, repeat_until: Time.utc(2026, 12, 31, 23, 59, 59))
  .to_rrule  # => "FREQ=DAILY;INTERVAL=1;UNTIL=20261231T235959Z"
```

## Time Projection

`RruleUtils` is an includable module for DST-aware time projection. Any object with a `recurrence` method returning a `Recurrence` can include it. The `Recurable` concern includes it automatically.

```ruby
# Project occurrences in a date range
model.recurrence_times(
  project_from: Time.zone.local(2026, 1, 1),
  project_to:   Time.zone.local(2026, 2, 1),
  dt_start_at:  model.created_at          # optional; defaults to project_from
)

# Find the last occurrence before a boundary
model.last_recurrence_time_before(Time.zone.now, dt_start_at: model.created_at)

# Find the next occurrence after a boundary
model.next_recurrence_time_after(Time.zone.now, dt_start_at: model.created_at)

# Human-readable description
model.humanize_recurrence  # => "every 3 months on the 15th"
```

Time projection delegates to the [rrule](https://github.com/square/ruby-rrule) gem with timezone-aware DST handling.

### DST Boundary Behavior

Daily and sub-daily recurrences behave differently across DST transitions.

**Spring forward** — On March 12, 2023 in `America/New_York`, clocks jump from 2:00 AM EST to 3:00 AM EDT.

A daily recurrence at 1:00 PM is unaffected — the wall-clock time stays consistent across the boundary:

```
Mar 11  1:00 PM EST
Mar 12  1:00 PM EDT  ← DST transition happened earlier this day, but 1 PM still fires
Mar 13  1:00 PM EDT
```

An hourly recurrence skips the non-existent 2:00 AM hour, producing 23 unique hours:

```
12:00 AM EST
 1:00 AM EST
 3:00 AM EDT  ← 2:00 AM doesn't exist, jumps straight to 3:00 AM
 4:00 AM EDT
 ...
11:00 PM EDT
```

**Fall back** — On November 5, 2023, clocks fall back from 2:00 AM EDT to 1:00 AM EST. The 1:00 AM hour occurs twice, but the duplicate is removed:

```
12:00 AM EDT
 1:00 AM EDT
 1:00 AM EST  ← duplicate wall-clock hour, removed by .uniq
 2:00 AM EST
 3:00 AM EST
 ...
11:00 PM EST
```

This produces 24 unique wall-clock hours despite the repeated 1:00 AM.

Try it yourself:

```ruby
Time.use_zone('America/New_York') do
  spring_forward = Time.zone.local(2023, 3, 12)

  # Daily at 1 PM: fires every day regardless of DST
  daily = Recurrence.new(frequency: 'DAILY', interval: 1)
  model = Struct.new(:recurrence).new(daily).extend(RruleUtils)
  model.recurrence_times(
    project_from: Time.zone.local(2023, 3, 11, 13),
    project_to:   Time.zone.local(2023, 3, 13, 13),
    dt_start_at:  Time.zone.local(2023, 3, 11, 13)
  ).map { |t| t.strftime('%b %d %l:%M %p %Z') }
  # => ["Mar 11  1:00 PM EST", "Mar 12  1:00 PM EDT", "Mar 13  1:00 PM EDT"]

  # Hourly on spring-forward day: 23 unique hours, 2 AM is skipped
  hourly = Recurrence.new(frequency: 'HOURLY', interval: 1)
  model  = Struct.new(:recurrence).new(hourly).extend(RruleUtils)
  hours  = model.recurrence_times(
    project_from: spring_forward.beginning_of_day,
    project_to:   spring_forward.end_of_day,
    dt_start_at:  spring_forward
  )
  hours.size # => 23

  # Hourly on fall-back day: 24 unique hours, duplicate 1 AM removed
  fall_back = Time.zone.local(2023, 11, 5)
  model = Struct.new(:recurrence).new(hourly).extend(RruleUtils)
  hours = model.recurrence_times(
    project_from: fall_back.beginning_of_day,
    project_to:   fall_back.end_of_day,
    dt_start_at:  Time.zone.local(2023, 11, 1)
  )
  hours.size # => 24
end
```

## The Recurable Concern

`Recurable` is an `ActiveSupport::Concern` included by ActiveRecord models with an `rrule` string column:

```ruby
class Plan < ApplicationRecord
  include Recurable
end
```

It provides:

1. **Serialization** — `serialize :rrule, RecurrenceSerializer` transparently converts between DB strings and `Recurrence` objects
2. **Delegation** — all `Recurrence` attributes and frequency predicates are delegated to the `rrule` object
3. **Validation** — recurrence attributes are validated with appropriate constraints (frequency inclusion, interval positivity, array value ranges, BYDAY pattern matching, COUNT/UNTIL mutual exclusivity)
4. **Time projection** — includes `RruleUtils` for `recurrence_times`, `last_recurrence_time_before`, `next_recurrence_time_after`, and `humanize_recurrence`

## Supported Frequencies

| Frequency | Period | Example |
|-----------|--------|---------|
| `YEARLY` | ~365 days | `FREQ=YEARLY;INTERVAL=1;BYMONTH=1,6` |
| `MONTHLY` | ~31 days | `FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15` |
| `WEEKLY` | 7 days | `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR` |
| `DAILY` | 1 day | `FREQ=DAILY;INTERVAL=1` |
| `HOURLY` | 1 hour | `FREQ=HOURLY;INTERVAL=4;BYMINUTE=0,30` |
| `MINUTELY` | 1 minute | `FREQ=MINUTELY;INTERVAL=15` |

## Constants

`Recurrence` exposes named constants for use in validations and logic:

```ruby
Recurrence::DAILY          # => "DAILY"
Recurrence::MONDAY         # => "MO"
Recurrence::SUNDAY         # => "SU"
Recurrence::MONTHLY_DATE   # => "DATE"
Recurrence::MONTHLY_NTH_DAY # => "NTH_DAY"
Recurrence::FREQUENCIES    # => {"YEARLY"=>365, "MONTHLY"=>31, ...}
Recurrence::DAYS_OF_WEEK   # => ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
Recurrence::NTH_DAY_OF_MONTH # => {first: 1, second: 2, ..., last: -1}
```

## Requirements

- Ruby >= 3.3
- ActiveModel >= 7.1
- ActiveSupport >= 7.1
- ActiveRecord >= 7.1 _(only if using the Recurable concern)_

## License

[MIT](LICENSE)
