# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Setup:**

```bash
cp .env.sample .env        # Configure environment variables
docker compose up -d       # Start PostgreSQL
bin/setup                  # Install deps, prepare DB, start server
bin/setup --skip-server    # Setup without starting server
```

**Development server:**

```bash
bin/dev                # Start via foreman (web + JS build + CSS build concurrently)
```

**Tests:**

```bash
bin/rails test                                    # All unit + integration tests
bin/rails test:system                             # System tests (Selenium/headless Chrome)
bin/rails test test/models/quote_test.rb          # Single file
bin/rails test test/models/quote_test.rb:42       # Single test by line number
bin/rails test:all                                # All tests including system
```

**Lint & security:**

```bash
bin/rubocop                    # RuboCop (omakase style)
bin/rubocop -a                 # Auto-fix offenses
bin/brakeman --no-pager        # Rails security scanner
bin/bundler-audit              # Gem vulnerability audit
bin/ci                         # Full local CI run
```

## Architecture

This is a Rails 8.1 app with a single `Quote` resource (name field). The stack uses:

- **Hotwire** (Turbo + Stimulus) for SPA-like interactions without a JS framework
- **Propshaft** as the asset pipeline (not Sprockets)
- **cssbundling-rails** with Sass and **jsbundling-rails** with esbuild — both run as separate watch processes via foreman (`bin/dev`)
- **simple_form** for form rendering, configured in `config/initializers/simple_form.rb`
- **PostgreSQL** for all environments

**CSS structure** is modular under `app/assets/stylesheets/`: `components/`, `config/`, `layouts/`, `mixins/`.

**Testing:** Minitest with parallel workers. System tests use Selenium + headless Chrome at 1400×1400 via `test/application_system_test_case.rb`.

**CSS imports** use `@use` (not `@import`) — Sass `@import` is deprecated. Each partial that uses a mixin must declare its own `@use`.
