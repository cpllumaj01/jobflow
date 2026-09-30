# JobFlow

JobFlow is a Ruby on Rails application for managing contractor workflows:

**Customer → Job → Estimate → Change Orders → Completion**

The job workspace brings project details, pricing, changes, and files together. The project demonstrates Rails domain modeling, relational data, authenticated ownership, nested resources, lifecycle actions, derived financial calculations, file handling, and a small JSON API.

## Features

- Session-based sign-in, registration, sign-out, and password reset.
- Customer management and jobs with status, address, and description.
- Estimates with quantity/unit-price line items and draft, sent, approved, and rejected statuses.
- Change orders with line items and draft, pending, approved, and rejected statuses.
- Contract values calculated from approved estimates and approved change orders.
- Dashboard counts for customers, jobs, active jobs, pending estimates, and pending changes, plus total current contract value.
- Job search by job name, address, or customer name, combined with status filtering.
- Multiple job attachments through Active Storage, with owner-only downloads and individual removal. Files are limited to 20 MB each; there is no content-type allowlist.
- Read-only, versioned Jobs API scoped to the signed-in user.

## Stack

Versions below come from `.ruby-version` and `Gemfile.lock`.

| Layer | Technology |
| --- | --- |
| Runtime | Ruby 4.0.7; Bundler 2.6.2 |
| Framework | Rails 8.1.3.1, Active Record, Puma |
| Database | PostgreSQL (`pg` 1.6.3; server version is not pinned) |
| Views and styling | ERB, Tailwind CSS 4.3.3 via `tailwindcss-rails` 4.6.0 |
| Browser behavior | Turbo, Stimulus via `stimulus-rails` 1.3.4, import maps |
| Files | Active Storage with local disk storage |
| Testing | Minitest model and controller/integration tests; Capybara 3.40.0 and Selenium are installed, but no system tests are currently defined |

JavaScript is served through import maps; the current development workflow does not require a Node package installation.

## Domain and implementation

```text
User
├── Sessions
└── Customers
    └── Jobs
        ├── Estimate → Estimate line items
        ├── Change orders → Change-order line items
        └── Files (Active Storage)
```

A job belongs to a customer, and a customer belongs to a user. Controllers load jobs through `Current.user.jobs` and nested resources through their owned job. Ownership is inherited rather than copied into redundant user columns.

Each job has at most one estimate and many change orders. Explicit actions mark estimates sent and change orders pending, or approve/reject either. Approved records cannot be edited until their status changes. These actions are separate from ordinary form parameters.

Contract values are computed by the Job model, not stored as additional database columns:

```text
Original estimate value = approved estimate total, otherwise zero
Approved changes = sum of approved change-order totals
Current contract value = original estimate value + approved changes
```

The UI uses server-rendered Rails forms. A small Stimulus controller debounces job searches by 300 ms, with Turbo updating the results. Dashboard and API queries preload pricing associations to avoid per-job queries. Attachment routes enforce Job ownership; default public Active Storage routes are disabled.

## Run locally

Install Ruby **4.0.7**, PostgreSQL, and the compiler/PostgreSQL client headers needed to build gems. Start PostgreSQL before preparing the database.

The development and test configuration in `config/database.yml` uses local PostgreSQL socket connections with a role matching your operating-system username. That role needs permission to create databases. If it is missing, a PostgreSQL administrator can create it with:

```sh
createuser --createdb YOUR_OS_USERNAME
```

Replace `YOUR_OS_USERNAME` with the account running Rails. If your PostgreSQL installation requires a host, username, or password, configure the local connection using the options described in `config/database.yml`; do not commit credentials. No application-specific environment variables are required for the default local setup.

From the repository root:

```sh
gem install bundler -v 2.6.2
bundle install
bin/rails db:prepare
bin/dev
```

Open http://localhost:3000. `bin/dev` starts Rails and the Tailwind watcher using `Procfile.dev`; it installs Foreman if it is missing. Development uploads are stored in `storage/`, and test uploads in `tmp/storage/`.

`db:prepare` creates the databases and loads the schema as needed, applies pending migrations, and loads seeds when initializing a new database. To apply subsequent migrations explicitly:

```sh
bin/rails db:migrate
```

The repository also provides `bin/setup --skip-server`, which installs missing gems, prepares the database, and clears logs/temp files. Run `bin/dev` afterward. To run Rails without the CSS watcher, first build styles with `bin/rails tailwindcss:build`, then run `bin/rails server`.

### Demo data

To load or refresh the demo explicitly:

```sh
bin/rails db:seed
```

**Development/demo-only login:** `demo@jobflow.test` / `password`.

Seeds create four customers, four jobs (kitchen renovation, bathroom remodel, office buildout, and deck replacement), four estimates, and two kitchen change orders. Their varied statuses demonstrate dashboard metrics and approved-versus-pending pricing.

Reseeding resets the demo password and deletes/recreates the demo account's customers and their nested project data. Other users' data is left alone. The seed script has no production-environment guard; use it only for local demonstrations.

## Read-only Jobs API

Sign in through the application, then open these URLs in the same browser session:

```http
GET /api/v1/jobs
GET /api/v1/jobs/:id
```

Both endpoints use the existing authenticated session, with no API token scheme. Only the signed-in user's jobs are returned. Unauthenticated requests redirect to sign-in. Missing jobs and another user's jobs both return HTTP 404 with `{"error":"Job not found"}`.

Representative index response (illustrative IDs and timestamps):

```json
{
  "jobs": [
    {
      "id": 1,
      "name": "Kitchen Renovation",
      "address": "123 Main Street",
      "status": "in_progress",
      "created_at": "2026-09-01T10:00:00.000Z",
      "updated_at": "2026-09-01T10:00:00.000Z",
      "customer": { "id": 1, "name": "Johnson Residence" },
      "original_estimate_value": "27000.0",
      "approved_change_order_total": "444.0",
      "current_contract_value": "27444.0"
    }
  ]
}
```

The show response uses a `job` wrapper with the same core fields, plus an `estimate` summary (`id`, `status`, `total`, or `null`) and a `change_orders` array (`id`, `title`, `status`, `total`). Monetary values are decimal strings. The index is unpaginated and ordered newest first. There are no API write endpoints.

## Tests

With PostgreSQL running:

```sh
bin/rails test
```

The suite covers authentication, registration, password reset, ownership isolation, nested-resource access, pricing/lifecycle behavior, attachments, search/filtering, and API responses. To run the API tests alone:

```sh
bin/rails test test/controllers/api/v1/jobs_controller_test.rb
```

## Screenshots

Screenshots have not been captured yet. Add images at the paths below and replace each placeholder with a Markdown image using that path.

| Screen | Suggested file | Capture |
| --- | --- | --- |
| Dashboard | `docs/screenshots/dashboard.png` | Metrics and current contract value |
| Job workspace | `docs/screenshots/job-workspace.png` | Job details, pricing summary, and attachments |
| Estimate | `docs/screenshots/estimate.png` | Line items, total, and lifecycle actions |
| Change Orders | `docs/screenshots/change-orders.png` | Changes and approval statuses |
