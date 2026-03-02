# Architecture

## System Overview

```
┌──────────────────────────────────────────────────────────┐
│                    ActiveRecord Model                    │
│                   (includes Recurable)                   │
│                                                          │
│  ┌──────────────────────┐   ┌──────────────────────────┐ │
│  │  RruleUtils          │   │  Recurable Concern       │ │
│  │  (included module)   │   │                          │ │
│  │                      │   │  • serialize :rrule      │ │
│  │  • recurrence_times  │   │  • delegate attributes   │ │
│  │  • last_recurrence_  │   │  • merge validations     │ │
│  │    time_before       │   │  • frequency? predicates │ │
│  │  • next_recurrence_  │   │                          │ │
│  │    time_after        │   └────────────┬─────────────┘ │
│  │  • humanize_         │                │               │
│  │    recurrence        │                │ serialize via │
│  └──────────┬───────────┘                │               │
│             │                            │               │
└─────────────┼────────────────────────────┼───────────────┘
              │ reads                      │
              │ self.recurrence            │
              ▼                            ▼
┌──────────────────────┐   ┌──────────────────────────────┐
│      rrule gem       │   │   RecurrenceSerializer       │
│ (square/ruby-rrule)  │   │                              │
│                      │   │  .load(string) → Recurrence  │
│ • RRule::Rule        │   │  .dump(recurrence) → string  │
│ • #between           │   │                              │
│ • #humanize          │   └───────────────┬──────────────┘
│                      │                   │
└──────────────────────┘                   │ delegates to
                                           ▼
                              ┌──────────────────────────┐
                              │        Recurrence        │
                              │  (pure Ruby data class)  │
                              │                          │
                              │ • RRULE ↔ attributes     │
                              │ • .from_rrule(string)    │
                              │ • #to_rrule → string     │
                              │ • Comparable by freq     │
                              │ • Constants & ranges     │
                              │ • Array coercion         │
                              └──────────────────────────┘
```

## Components

### Recurrence (`lib/recurable/recurrence.rb`)

Pure Ruby data class with no Rails dependencies. Represents an iCal RRULE as named Ruby attributes.

**Responsibilities:**

- Bidirectional RRULE string conversion (`#to_rrule`, `.from_rrule`)
- Attribute storage with coercion (array wrapping, UTC time normalization)
- Input guarding (`ArgumentError` on unknown attributes)
- Frequency comparison via `Comparable` (YEARLY < MONTHLY < ... < MINUTELY)
- Constants for all valid values (frequencies, days, ranges, patterns)

**Key internals:**

- `ARRAY_ATTRIBUTES` — attributes that accept arrays; setters auto-wrap scalars and normalize `[]` to `nil`
- `FREQ_ORDER` — hash mapping frequency strings to sort indices for `<=>`
- `BYDAY_PATTERN` — regex validating BYDAY values like `MO`, `+2TH`, `-1FR`
- `UNTIL_PATTERN` — regex parsing RRULE date strings (`YYYYMMDDTHHMMSSZ`) into Time objects
- `parse_components` / `attributes_from` — private class methods that split an RRULE string into a component hash, then map components to attribute names

### Recurable Concern (`lib/recurable.rb`)

ActiveSupport::Concern included by ActiveRecord models with an `rrule` string column.

**Responsibilities:**

- Declares `serialize :rrule, RecurrenceSerializer` with a sensible default
- Delegates all Recurrence attributes and frequency predicates to the `rrule` object
- Defines validations for all recurrence attributes using standard `validates`/`validate` declarations
- Includes `RruleUtils` for time projection and humanization
- Creates `alias_attribute :recurrence, :rrule` so RruleUtils can call `self.recurrence`

### RruleUtils (`lib/recurable/rrule_utils.rb`)

Includable module for DST-aware time projection and humanization. Expects the including object to respond to `recurrence` returning a `Recurrence`.

**Methods:**

- `recurrence_times(project_from:, project_to:, dt_start_at:)` — projects occurrence times in a range using the rrule gem's timezone-aware engine. Deduplicates results to handle DST transitions.
- `last_recurrence_time_before(before, dt_start_at:)` — finds the most recent occurrence before a boundary by projecting backwards over one full interval period.
- `next_recurrence_time_after(after, dt_start_at:)` — finds the first occurrence after a boundary by projecting forwards over one full interval period.
- `humanize_recurrence` — delegates to `RRule::Rule#humanize` for a human-readable description.

**Design:** The module is decoupled from ActiveRecord. Any object (Struct, PORO, etc.) can include it as long as it provides a `recurrence` method.

### RecurrenceSerializer (`lib/recurable/recurrence_serializer.rb`)

Bridges `ActiveRecord::Base.serialize` between RRULE strings stored in the database and `Recurrence` objects in Ruby.

**Methods:**

- `.load(string)` — parses an RRULE string into a `Recurrence` via `Recurrence.from_rrule`; returns `nil` for blank input
- `.dump(recurrence)` — serializes a `Recurrence` to an RRULE string via `#to_rrule`; returns `nil` for `nil` input

### ArrayInclusionValidator (`lib/recurable/array_inclusion_validator.rb`)

Custom ActiveModel validator that checks each element of an array attribute against an allowed set. Supports both enumerable collections (Range, Array) via `#include?` and Regexp via `#match?`.

## Data Flow

### Write Path (model → database)

```
plan.frequency = 'MONTHLY'     # delegated to plan.rrule.frequency=
plan.by_month_day = [15]       # delegated to plan.rrule.by_month_day= (coerced to array)
plan.save!
  → plan.valid?                # Recurable validates attributes
  → RecurrenceSerializer.dump  # calls plan.rrule.to_rrule
  → "FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15"  # stored in DB
```

### Read Path (database → model)

```
Plan.find(1)
  → RecurrenceSerializer.load("FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15")
  → Recurrence.from_rrule(...)  # parses components → attributes
  → plan.rrule = #<Recurrence>  # Recurrence object with named attributes
plan.by_month_day              # => [15] (delegated to plan.rrule.by_month_day)
```

### Time Projection Path

```
plan.recurrence_times(project_from:, project_to:, dt_start_at:)
  → RruleUtils#recurrence_times
  → RRule::Rule.new(plan.recurrence.to_rrule, dtstart:, tzid:)
  → rule.between(from, to)  # rrule gem handles DST
  → .uniq                   # dedup DST edge cases
  → [Time, Time, ...]       # timezone-aware occurrences
```

## Design Decisions

### Declarative Validations

The concern uses standard `validates` and `validate` declarations in its `included` block, which register directly on the host model's validation chain. This is simpler than overriding `valid?` and chaining via `super`.

### Array Coercion

All RRULE components that accept multiple values (BYDAY, BYMONTHDAY, BYSETPOS, etc.) are stored as arrays. Setters coerce scalars to single-element arrays and normalize empty arrays to `nil`. This simplifies RRULE generation — `join_list` always operates on arrays or nil.

### UTC for UNTIL

`repeat_until` is always stored as UTC Time, matching the RRULE spec's `UNTIL=YYYYMMDDTHHMMSSZ` format. The setter accepts both Time objects (converted to UTC) and RRULE date strings (parsed).

### Attribute Names Align with RRULE

Attribute names mirror their RRULE component names: `by_day` (BYDAY), `by_month_day` (BYMONTHDAY), `by_set_pos` (BYSETPOS), `month_of_year` (BYMONTH), etc. This makes the mapping between Ruby attributes and RRULE strings obvious.

### No ActiveRecord Runtime Dependency

Only `activemodel` and `activesupport` are runtime dependencies. `activerecord` is a development dependency for testing the concern's `serialize` call. This allows standalone use of `Recurrence` and `RruleUtils` without Rails.

### Comparable Frequency Ordering

`Recurrence` includes `Comparable` with ordering from least frequent (YEARLY) to most frequent (MINUTELY). The `FREQ_ORDER` hash maps frequency strings to numeric indices for the `<=>` operator. This supports strategy selection and sorting.

### Guarded Constructor

`Recurrence.new` raises `ArgumentError` for unknown keyword arguments, catching typos and stale attribute names at construction time rather than silently ignoring them.
