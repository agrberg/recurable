# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Recurable is a Ruby gem that provides iCal RRULE recurrence with optional Rails/ActiveRecord integration. The core library (`Recurrence`, `RruleUtils`, `RecurrenceSerializer`) only requires ActiveModel and ActiveSupport. The `Recurable` concern adds ActiveRecord integration for models with an `rrule` string column. Targets Ruby 3.3+ and Rails 7.1+.

**Two entry points:**
- `require 'recurable/recurrence'` — standalone, no Rails needed
- `require 'recurable'` — loads everything including the ActiveRecord concern

## Commands

```bash
bundle install                          # Install dependencies
bundle exec rake                        # Default task: runs RSpec + RuboCop
bundle exec rspec                       # Run all tests
bundle exec rspec spec/recurrence_spec.rb:42  # Run single test by line
bundle exec rubocop                     # Lint
bundle exec rubocop -A                  # Lint with autofix
COVERAGE=true bundle exec rspec         # Run tests with coverage report
```

## Architecture

```
ActiveRecord model (prepends Recurable)
  ├─ include RruleUtils                        ← time projection, humanization (includable module)
  └─ serialize :rrule, RecurrenceSerializer    ← converts DB string ↔ Recurrence object
       └─ Recurrence (ActiveModel)             ← validates, generates/parses RRULE strings
```

**Key files:**
- `lib/recurable.rb` — Recurable concern: serialization, delegation, validation merging, `frequency?` methods
- `lib/recurable/recurrence.rb` — Core model: RRULE parsing/generation, constants, validations
- `lib/recurable/rrule_utils.rb` — Includable module: DST-aware time projection, humanization (expects `self.recurrence` to return a Recurrence)
- `lib/recurable/recurrence_serializer.rb` — `load`/`dump` bridge between RRULE strings and Recurrence objects

## Key Design Decisions

- **Concern is prepended, not included** — allows `valid?` override that chains with the host model's validation via `super`
- **RruleUtils is an includable module** — any object responding to `recurrence` (returning a Recurrence) can include it; the concern includes it automatically via `alias_attribute :recurrence, :rrule`
- **`serialize` with `default:` keyword** — requires Rails 7.1+; this is why 7.0 is not compatible
- **`activerecord` is NOT a runtime dependency** — only `activemodel` and `activesupport` are runtime deps; `activerecord` is a development dependency for testing the concern's `serialize` call
- **`Comparable` on Recurrence** — compares by frequency order (YEARLY < MONTHLY < ... < MINUTELY)
- **`date_of_month` vs `day_of_month`** — confusingly, `date_of_month` is a numeric day (1–28) while `day_of_month` is an array of day-of-week strings (SU/MO/etc.) used in monthly nth-day recurrences
- **`day_of_week` and `day_of_month` are arrays** — BYDAY supports multi-value (e.g., `MO,WE,FR`); array setters coerce scalars to single-element arrays
- **`count` vs `repeat_until`** — mutually exclusive per RFC 5545; validated in the concern
- **`repeat_until`** — stored as UTC Time; the setter accepts Time objects or RRULE date strings (`YYYYMMDDTHHMMSSZ`)
- **Full RFC 5545 RRULE support** — all 14 components: FREQ, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY, BYMONTH, BYHOUR, BYMINUTE, BYSECOND, BYYEARDAY, BYWEEKNO, BYSETPOS, WKST

## Testing Notes

- DST edge cases in `rrule_utils_spec.rb` run in `America/New_York` timezone via `Time.use_zone()`
- Time projection tests in `recurrence_spec.rb` run in `America/Chicago` timezone
- DST spring-forward and fall-back transitions are explicitly tested, plus non-DST baselines
- `recurrence_serializer_spec.rb` covers nil/empty/round-trip serialization
- No ActiveRecord integration tests — the concern is tested indirectly through Recurrence validation
