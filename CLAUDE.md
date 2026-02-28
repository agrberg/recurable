# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Recurable is a Ruby gem that provides iCal RRULE recurrence with optional Rails/ActiveRecord integration. The core library (`Recurrence`, `RruleAdapter`, `RecurrenceSerializer`) only requires ActiveModel and ActiveSupport. The `Recurable` concern adds ActiveRecord integration for models with an `rrule` string column. Targets Ruby 3.3+ and Rails 7.1+.

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
  └─ serialize :rrule, RecurrenceSerializer  ← converts DB string ↔ Recurrence object
       └─ Recurrence (ActiveModel)           ← validates, generates/parses RRULE strings
            └─ RruleAdapter                  ← projects occurrence times with DST handling
                 ├─ RRule gem (daily+)       ← ignores DST by design
                 └─ IceCube gem (hourly/minutely) ← needs manual DST offset adjustment
```

**Key files:**
- `lib/recurable.rb` — Recurable concern: serialization, delegation, validation merging, `frequency?` methods
- `lib/recurable/recurrence.rb` — Core model: RRULE parsing/generation, constants, validations, I18n statements
- `lib/recurable/rrule_adapter.rb` — DST-aware time projection (the trickiest code in the gem)
- `lib/recurable/recurrence_serializer.rb` — `load`/`dump` bridge between RRULE strings and Recurrence objects
- `lib/recurable/railtie.rb` — Loads I18n locale files in Rails
- `config/locales/en.yml` — Frequency noun translations for `recurrence_statement`

## Key Design Decisions

- **Concern is prepended, not included** — allows `valid?` override that chains with the host model's validation via `super`
- **Dual adapter strategy** — RRule gem for daily+ frequencies (DST-safe by ignoring offsets), IceCube for hourly/minutely (requires manual UTC offset adjustment at DST boundaries)
- **`serialize` with `default:` keyword** — requires Rails 7.1+; this is why 7.0 is not compatible
- **`activerecord` is NOT a runtime dependency** — only `activemodel` and `activesupport` are runtime deps; `activerecord` is a development dependency for testing the concern's `serialize` call
- **`Comparable` on Recurrence** — compares by frequency order (YEARLY < MONTHLY < ... < MINUTELY); used by RruleAdapter to decide which projection strategy to use
- **`date_of_month` vs `day_of_month`** — confusingly, `date_of_month` is a numeric day (1–28) while `day_of_month` is a day-of-week string (SU/MO/etc.) used in monthly nth-day recurrences

## Testing Notes

- DST edge cases in `rrule_adapter_spec.rb` run in `America/New_York` timezone via `Time.use_zone()`
- Time projection tests in `recurrence_spec.rb` run in `America/Chicago` timezone
- DST spring-forward and fall-back transitions are explicitly tested, plus non-DST baselines
- `recurrence_serializer_spec.rb` covers nil/empty/round-trip serialization
- No ActiveRecord integration tests — the concern is tested indirectly through Recurrence validation
