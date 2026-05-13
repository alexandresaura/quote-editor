# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**First-time setup:**

```bash
cp .env.sample .env             # only ENV var is DATABASE_URL
docker compose up -d            # PostgreSQL 17 on :5432, trust auth
bin/setup [--skip-server] [--reset]
```

`bin/setup` runs `bundle install`, `yarn install`, `db:prepare`, clears logs/tmp, and `exec`s into `bin/dev` unless `--skip-server`. `--reset` adds `db:reset`.

**Development:**

```bash
bin/dev                         # foreman: rails server + esbuild --watch + sass --watch
                                # `web` proc runs with RUBY_DEBUG_OPEN=true (remote debugger)
```

**Tests** (Minitest, parallel workers, `fixtures :all`):

```bash
bin/rails test                                    # models + controllers
bin/rails test:system                             # Selenium + headless Chrome @ 1400x1400
bin/rails test test/models/quote_test.rb          # single file
bin/rails test test/models/quote_test.rb:4        # single test by line
bin/rails test:all                                # everything including system
```

**Lint / security / CI:**

```bash
bin/rubocop                     # rubocop-rails-omakase style (no custom rules)
bin/rubocop -a                  # autofix
bin/brakeman --no-pager
bin/bundler-audit               # ignore list at config/bundler-audit.yml
bin/ci                          # ActiveSupport::ContinuousIntegration runner, steps in config/ci.rb
```

`bin/ci` runs setup, rubocop, gem audit, `yarn audit`, brakeman, `bin/rails test`, and `db:seed:replant`. System tests are intentionally commented out — they only run in the dedicated `system-test` GitHub job (`.github/workflows/ci.yml`).

**Other:**

```bash
bin/jobs                        # Solid Queue worker
bin/kamal <cmd>                 # deploy (config/deploy.yml — registry/servers are placeholders)
bin/rails db:seed               # loads test/fixtures/*.yml as dev data (db/seeds.rb)
```

## Architecture

Rails 8.1 app for building multi-line, multi-date price quotes. Two cross-cutting concerns shape almost everything: **multi-tenancy through `Company`** and **Hotwire-first responses**.

### Domain model

```
Company ─┬── has_many :users
         └── has_many :quotes (dependent: :destroy)
                       └── has_many :line_item_dates (dependent: :destroy)
                                    └── has_many :line_items   (dependent: :destroy)
Quote.has_many :line_items, through: :line_item_dates
```

`Quote#total_price` sums `line_items.sum(&:total_price)`. `LineItem#total_price = quantity * unit_price`. `LineItemDate` has `previous_date` (last date before `self.date` on the same quote) — used by Turbo Stream templates to insert new/updated dates in the right position.

Routes mirror the nesting (`config/routes.rb`):

```
quotes > line_item_dates (no index/show) > line_items (no index/show)
+ singular `session`, `passwords` (param: :token), `pages#home` at root
```

### Multi-tenancy (load-bearing)

`Current` (`app/models/current.rb`) is an `ActiveSupport::CurrentAttributes` holding `session` and delegating `user` (→ session) and `company` (→ user). **Every read or write of company-owned data goes through `Current.company`**: e.g. `Current.company.quotes.find(params[:id])`, never `Quote.find`. The nested controllers chain through the parent association (`@quote.line_item_dates.find(...)`, `@line_item_date.line_items.find(...)`), so the tenant scope propagates. The `pwc:eavesdropper` fixture lives in a separate company from the `kpmg` fixtures for cross-tenant tests.

`Quote` broadcasts via `broadcasts_to ->(quote) { [quote.company, "quotes"] }, inserts_by: :prepend`. The index view subscribes with `turbo_stream_from Current.company, "quotes"` — channel names are namespaced by company, so live updates don't leak across tenants either.

### Authentication

Rails 8's built-in auth pattern. Key pieces:

- `Authentication` concern (`app/controllers/concerns/authentication.rb`) is included in `ApplicationController` and installs a global `before_action :require_authentication`.
- Public endpoints opt out per controller via `allow_unauthenticated_access [only:|except:]` (used by `SessionsController#new/create`, `PasswordsController`, `PagesController#home`).
- Sessions are DB rows (`Session` model) keyed by signed cookie `session_id`; `start_new_session_for` records `user_agent`/`ip_address`, `terminate_session` destroys + clears cookie.
- `User` uses `has_secure_password`, `normalizes :email_address`, and `User.authenticate_by(...)` for login.
- Password reset uses signed tokens via `User.find_by_password_reset_token!` (Rails 8 `generates_token_for`-derived).
- Rate limit: `rate_limit to: 10, within: 3.minutes` on session create and password create.
- `ApplicationCable::Connection` does its own `Session.find_by(id: cookies.signed[:session_id])` — keep it in sync if you change session lookup logic.

### Hotwire patterns

Controllers respond to **both** `html` (redirect with `notice:`) and `turbo_stream` (sets `flash.now[:notice]`) inside `respond_to`. The Turbo Stream branch renders a matching `*.turbo_stream.erb`. Conventions you'll see everywhere:

- **Inline forms via Turbo Frames**: "New X" links target `dom_id(X.new)` (e.g. `turbo_frame: dom_id(Quote.new)`), and the view places a `turbo_frame_tag X.new` placeholder where the form lands. The corresponding `create.turbo_stream.erb` calls `turbo_stream.update X.new, ""` to close the form.
- **Flash through Turbo**: every `*.turbo_stream.erb` starts with `<%= render_turbo_stream_flash_messages %>` (`ApplicationHelper`). It prepends a partial into `<div id="flash">`. Flash messages auto-remove via the `removals_controller` Stimulus controller on `animationend` (`app/views/layouts/_flash.html.erb`).
- **Live broadcasting**: `Quote` broadcasts to its company's stream; index page subscribes.
- **Ordered insertion**: `line_item_dates/create.turbo_stream.erb` checks `previous_date` to decide between `turbo_stream.after previous_date` (insert mid-list) and `turbo_stream.prepend "line_item_dates"` (insert first). `update.turbo_stream.erb` removes then re-inserts so the order updates when the date field changes. Replicate this pattern when adding ordered nested resources.
- **Total recomputation**: any line-item create/destroy emits a `turbo_stream.update dom_id(@quote, :total)` re-rendering the `quotes/_total` partial. The total is wrapped in its own frame on `quotes/show`.
- **`nested_dom_id` helper**: builds compound ids like `line_item_date_42_new_line_item` for the nested-resource frames (`app/helpers/application_helper.rb`).
- **Stimulus controllers are registered by hand**: the comment in `app/javascript/controllers/index.js` says "auto-generated by stimulus:manifest:update" but the file is edited manually here — when adding a controller, add the `import` + `application.register(...)` line yourself.

### Forms and views

`simple_form` configured in `config/initializers/simple_form.rb`: wrapper is `form__group`, labels are `visually-hidden` (placeholders carry the label visually), button class `btn`. Per-resource labels/placeholders/submit text live in `config/locales/simple_form.en.yml` — add entries there when introducing a new form, not in views.

`form_error_notification(object)` (in `ApplicationHelper`) renders a single `.error-message` div with the full sentence of errors; place it at the top of every form partial. On failed save, controllers render `:new`/`:edit` with `status: :unprocessable_entity` (required for Turbo to render the form errors instead of following the redirect).

### Assets

Propshaft + cssbundling-rails (Sass) + jsbundling-rails (esbuild). Watchers run in parallel via `Procfile.dev`. CSS entry: `app/assets/stylesheets/application.sass.scss`, structured as `config/`, `components/`, `layouts/`, `mixins/`, `utilities/`. **Always use `@use`** (Sass `@import` is deprecated and not used in this repo) — each partial that needs a mixin or variable must declare its own `@use "../mixins/media" as *;` style import. The lone responsive mixin is `media(tabletAndUp)` → `@media (min-width: 50rem)`.

### Testing notes

- Two `sign_in_as` helpers — pick by test type:
  - Integration/controller tests → `SessionTestHelper` (`test/test_helpers/session_test_helper.rb`), auto-included into `ActionDispatch::IntegrationTest` via `on_load`.
  - System tests → `ApplicationSystemTestCase#sign_in_as` (Selenium cookie injection after visiting `new_session_path`).
- Fixtures hard-code the password to `"password"` via `BCrypt::Password.create` in `test/fixtures/users.yml`.
- Company-scoped fixtures: `kpmg` (accountant, manager) and `pwc` (eavesdropper). Use the `pwc` user when writing cross-tenant tests.
- Quote `:first` is wired up so `total_price == 2500` (2 dates × (1×1000 + 10×25)).
- System tests upload `tmp/screenshots` on failure via CI artifact.

### Infrastructure

- **PostgreSQL is the only datastore.** Solid Queue / Solid Cache / Solid Cable all run against the primary DB in dev/test; production uses separate logical databases (`config/database.yml`, `config/queue.yml`, `config/cable.yml`).
- **Deploy via Kamal**, fronted by Thruster (HTTP caching + X-Sendfile for Puma). `SOLID_QUEUE_IN_PUMA=true` in `config/deploy.yml` — jobs run in-process with web until you split them out.
- Browser support is gated by `allow_browser versions: :modern` in `ApplicationController` (requires webp, web push, badges, import maps, CSS nesting, `:has`).

## Gotchas

- **Scope all company-owned reads/writes through `Current.company`** (or the parent association). This is how tenant isolation is enforced.
- **Turbo Stream branches use `flash.now`**, matching every controller in the codebase.
- **Failed saves render with `status: :unprocessable_entity`** so Turbo renders the errored form instead of following the redirect.
- **Stimulus manifest is edited by hand**: add `import` + `application.register(...)` lines to `app/javascript/controllers/index.js` yourself.
- **Mailer host** is set to `localhost:3000` in `config/environments/development.rb`; password-reset links use it.
