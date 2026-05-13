# Quote Editor

A multi-tenant Rails app for building multi-line, multi-date price quotes. Each `Company` owns its `Users` and `Quotes`; a `Quote` is composed of `LineItemDate`s (one per delivery date), each holding ordered `LineItem`s with name, quantity, and unit price.

## Stack

- **Ruby** 4.0.1, **Node** 25.8.1
- **Rails** 8.1, **PostgreSQL** 17
- **Hotwire** (Turbo + Stimulus) with `cssbundling-rails` (Sass) and `jsbundling-rails` (esbuild)
- **Propshaft** asset pipeline
- **simple_form** for forms
- **Solid Queue / Solid Cache / Solid Cable** (database-backed adapters)
- **Kamal** + **Thruster** for deployment
- **Minitest**, **Capybara**, **Selenium** (headless Chrome) for tests
- **rubocop-rails-omakase**, **brakeman**, **bundler-audit**

## Prerequisites

- Ruby 4.0.1 (pinned in `.ruby-version`)
- Node 25.8.1 (pinned in `.node-version`) and Yarn
- Docker (for the PostgreSQL container) — or a local PostgreSQL 17 instance

## Setup

```bash
cp .env.sample .env       # sets DATABASE_URL
docker compose up -d      # starts PostgreSQL on :5432
bin/setup                 # installs gems & JS deps, prepares the DB, starts the dev server
```

Useful flags:

- `bin/setup --skip-server` — set up without starting the dev server
- `bin/setup --reset` — drop and recreate the database

Seed the database with the test fixtures (KPMG/PwC companies, sample users, quotes, line items):

```bash
bin/rails db:seed
```

Default fixture password: `password`. Example user: `accountant@kpmg.com`.

## Development

```bash
bin/dev
```

Runs three processes via `foreman` (`Procfile.dev`): the Rails server (with `RUBY_DEBUG_OPEN=true`), `esbuild --watch`, and `sass --watch`.

## Tests

```bash
bin/rails test            # models + controllers (parallel workers)
bin/rails test:system     # system tests via Selenium + headless Chrome
bin/rails test:all        # everything

bin/rails test test/models/quote_test.rb       # single file
bin/rails test test/models/quote_test.rb:4     # single test by line
```

## Lint and security

```bash
bin/rubocop               # rubocop-rails-omakase style
bin/rubocop -a            # autofix
bin/brakeman --no-pager
bin/bundler-audit         # ignore list at config/bundler-audit.yml
bin/ci                    # full local CI run (config/ci.rb)
```

GitHub Actions runs `scan_ruby`, `lint`, `test`, and `system-test` jobs on every push to `main` and on pull requests (`.github/workflows/ci.yml`).

## Background jobs

```bash
bin/jobs                  # Solid Queue worker
```

In production, `SOLID_QUEUE_IN_PUMA=true` (see `config/deploy.yml`) runs the supervisor inside the web server's Puma process.

## Deployment

Deployed with Kamal. Edit `config/deploy.yml` (servers, registry, env) and `.kamal/secrets`, then:

```bash
bin/kamal setup           # first deploy
bin/kamal deploy          # subsequent deploys
bin/kamal console         # rails console on the server
bin/kamal logs            # tail logs
```

Thruster fronts Puma for HTTP caching, compression, and X-Sendfile acceleration.
