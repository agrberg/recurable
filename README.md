# Recurable

iCal RRULE recurrence library for Ruby with optional Rails/ActiveRecord integration.

## Quick Start: Standalone

No Rails required. Just ActiveModel and ActiveSupport.

```ruby
require 'recurable/recurrence'

# Build a recurrence from attributes
recurrence = Recurrence.new(frequency: 'DAILY', interval: 1)
recurrence.rrule    # => "FREQ=DAILY;INTERVAL=1"
recurrence.valid?   # => true

# Parse an existing RRULE string
recurrence = Recurrence.from_rrule(rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO')
recurrence.frequency   # => "WEEKLY"
recurrence.interval    # => 2
recurrence.day_of_week # => "MO"

# Project occurrence times within a date range
recurrence.recurrence_times(
  project_from: Time.zone.local(2026, 1, 1),
  project_to:   Time.zone.local(2026, 2, 1)
)
```

## Quick Start: With Rails

Add the gem, then prepend the `Recurable` concern on any model with an `rrule` string column:

```ruby
class Plan < ApplicationRecord
  prepend Recurable
end

plan = Plan.new
plan.frequency = 'MONTHLY'
plan.interval = 3
plan.date_of_month = 15
plan.rrule          # => #<Recurrence> with rrule "FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=15"
plan.valid?         # validates both the model and the recurrence
plan.monthly?       # => true
plan.recurrence_statement # => "Repeats every 3 months."
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

# Also add activerecord if not already present:
gem 'activerecord', '>= 7.1'

# Then in your code (or it auto-loads via Railtie):
require 'recurable'
```

## How It Works

### The Recurrence Object

`Recurrence` is an ActiveModel object with named attributes for building RRULE strings. The naming conventions can be confusing, so here's a guide:

| Attribute | Type | RRULE Component | Used When | Example |
|-----------|------|-----------------|-----------|---------|
| `frequency` | String | `FREQ` | Always | `"MONTHLY"` |
| `interval` | Integer | `INTERVAL` | Always | `3` |
| `date_of_month` | Integer (1-28) | `BYMONTHDAY` | Monthly by date | `15` (the 15th) |
| `day_of_month` | String (SU/MO/...) | `BYDAY` | Monthly by nth day | `"TU"` (Tuesday) |
| `nth_day_of_month` | Integer | `BYSETPOS` | Monthly by nth day | `2` (2nd), `-1` (last) |
| `day_of_week` | String (SU/MO/...) | `BYDAY` | Weekly | `"MO"` (Monday) |
| `minute_of_hour` | Integer (0-59) | `BYMINUTE` | Hourly | `30` |
| `monthly_option` | String | _(internal)_ | Monthly | `"DATE"` or `"NTH_DAY"` |

**Why `date_of_month` vs `day_of_month`?** `date_of_month` is a calendar date number ("the 15th"), while `day_of_month` is a weekday name used with `nth_day_of_month` ("the 2nd Tuesday"). Both are for monthly recurrences but serve different monthly options.

### RRULE Parsing & Generation

```ruby
# Generate: attributes → RRULE string
recurrence = Recurrence.new(frequency: 'MONTHLY', interval: 1, day_of_month: 'FR', nth_day_of_month: -1)
recurrence.rrule # => "FREQ=MONTHLY;INTERVAL=1;BYDAY=FR;BYSETPOS=-1"

# Parse: RRULE string → attributes
parsed = Recurrence.from_rrule(rrule: 'FREQ=MONTHLY;INTERVAL=1;BYDAY=FR;BYSETPOS=-1')
parsed.day_of_month    # => "FR"
parsed.nth_day_of_month # => -1
parsed.monthly_option   # => "NTH_DAY"

# Round-trip
parsed.rrule == recurrence.rrule # => true
```

### Time Projection

`RruleAdapter` projects occurrence times within a date range, using a dual-adapter strategy:

- **Daily or slower** (YEARLY, MONTHLY, WEEKLY, DAILY): Delegates to the [rrule](https://github.com/square/ruby-rrule) gem, which safely ignores DST transitions and keeps wall-clock hours consistent.
- **Hourly or faster** (HOURLY, MINUTELY): Delegates to [ice_cube](https://github.com/ice-cube-ruby/ice_cube), then manually adjusts UTC offsets so that "every 1 hour" means every wall-clock hour, even across DST boundaries.

The split exists because the rrule gem's offset-ignoring behavior is correct for day-level frequencies but produces duplicate/missing hours at sub-day frequencies.

### DST Handling

The `dst_adjustment` mechanism compares the UTC offset of `dt_start_at` (the recurrence anchor date) with each projected time's UTC offset:

**Spring forward** (ST → DST): On 2023-03-12 in Eastern Time, 2:00 AM doesn't exist. The adapter's adjustment maps both the would-be 2 AM and 3 AM to the same wall-clock time, then deduplicates via `.uniq` — producing 23 hours instead of 24.

**Fall back** (DST → ST): On 2023-11-05, 1:00 AM occurs twice. The adjustment ensures each wall-clock hour appears exactly once — producing 24 hours.

### The Recurable Concern

`Recurable` is an `ActiveSupport::Concern` designed to be **prepended** (not included) on ActiveRecord models:

```ruby
class Plan < ApplicationRecord
  prepend Recurable
end
```

Prepending (vs including) allows the concern to override `valid?` and chain with the host model's validations via `super`. It:

1. Declares `serialize :rrule, RecurrenceSerializer` so the DB column transparently round-trips through `Recurrence` objects
2. Delegates recurrence attributes to the `rrule` object (so `plan.frequency` works)
3. Merges recurrence validation errors into the model's errors
4. Defines `frequency?` predicates (`plan.daily?`, `plan.yearly?`, etc.)

### RecurrenceSerializer

Bridges `ActiveRecord::Base.serialize` between RRULE strings in the database and `Recurrence` objects in Ruby:

```ruby
RecurrenceSerializer.load('FREQ=DAILY;INTERVAL=1')
# => #<Recurrence frequency="DAILY" interval=1>

RecurrenceSerializer.dump(Recurrence.new(frequency: 'DAILY', interval: 1))
# => "FREQ=DAILY;INTERVAL=1"
```

## Supported Frequencies

| Frequency | Adapter | DST Strategy |
|-----------|---------|-------------|
| YEARLY | rrule gem | Ignored (day-level) |
| MONTHLY | rrule gem | Ignored (day-level) |
| WEEKLY | rrule gem | Ignored (day-level) |
| DAILY | rrule gem | Ignored (day-level) |
| HOURLY | ice_cube + manual adjustment | `dst_adjustment` offset correction |
| MINUTELY | ice_cube + manual adjustment | `dst_adjustment` offset correction |

## Requirements

- Ruby >= 3.3
- ActiveModel >= 7.1
- ActiveSupport >= 7.1
- ActiveRecord >= 7.1 _(only if using the Recurable concern)_

## License

[MIT](LICENSE)
