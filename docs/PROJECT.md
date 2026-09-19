# JobFlow

JobFlow is a portfolio-focused Ruby on Rails application for contractors to manage customers, jobs, estimates, change orders, and project documentation.

The goal is to demonstrate production-quality Rails development through realistic business workflows without turning the project into an unnecessarily large SaaS platform.

## Core Workflow

Customer → Job → Estimate → Approved Work → Change Orders → Completion

## Core Features

JobFlow should allow an authenticated user to:

* Create and manage customers
* Create jobs for customers
* Create one estimate per job
* Add estimate line items
* Calculate estimate totals from line items
* Approve or reject estimates
* Create change orders with line items
* Approve or reject change orders
* Track original estimate value
* Track approved change-order value
* Calculate current contract value
* Search and filter jobs
* Upload job and change-order documentation
* View a useful dashboard
* Access a small JSON API for jobs

## Data Ownership

All business data belongs to a User.

Current ownership hierarchy:

User
→ Customers
→ Jobs
→ Estimate
→ EstimateLineItems

Jobs are owned indirectly through Customers rather than having a redundant `user_id`.

User-owned records must always be scoped so one user cannot access another user's data by manipulating IDs.

For example:

```ruby
Current.user.customers.find(params[:id])
Current.user.jobs.find(params[:id])
```

## Models

### User

Owns Customers and has Jobs through Customers.

### Customer

Fields include:

* name
* contact_name
* email
* phone
* address
* notes

A Customer belongs to a User and has many Jobs.

### Job

Fields include:

* customer_id
* name
* description
* address
* status
* start_date
* estimated_completion_date
* completed_at

Statuses:

* draft
* quoted
* approved
* in_progress
* completed
* cancelled

A Job belongs to a Customer and has one Estimate.

Eventually a Job should expose:

* original estimate value
* approved change-order total
* current contract value

### Estimate

A Job has at most one Estimate.

Fields include:

* status
* notes
* expires_on
* approved_at

Statuses:

* draft
* sent
* approved
* rejected

Estimate totals are derived from line items and are not persisted.

### EstimateLineItem

Fields:

* description
* quantity
* unit_price

Line total is calculated as:

quantity × unit_price

Money and quantities use decimal values rather than floats.

### ChangeOrder

Planned model belonging to Job.

Expected fields:

* title
* description
* status
* requested_at
* approved_at

Statuses:

* draft
* pending
* approved
* rejected

### ChangeOrderLineItem

Planned model belonging to ChangeOrder.

Fields:

* description
* quantity
* unit_price

## Contract Value

Planned semantics:

* Original estimate value: approved estimate total
* Approved change-order total: total of approved change orders
* Current contract value: approved estimate value + approved change-order total

Draft or rejected work should not contribute to current contract value.

## Authentication and Security

JobFlow uses Rails authentication.

The application supports:

* Sign up
* Login
* Logout
* Password reset

Ownership scoping is a critical requirement.

A user must not be able to access another user's Customers, Jobs, Estimates, or future Change Orders by changing URL parameters or submitted foreign keys.

## Testing

Use Minitest and Capybara/system tests.

Tests should verify meaningful behavior rather than exist only for coverage.

Important workflows should eventually include:

User logs in
→ creates customer
→ creates job
→ creates estimate
→ adds line items
→ approves estimate
→ creates change order
→ approves change order
→ contract value updates

Security tests should explicitly verify cross-user access is rejected.

## Engineering Approach

Prefer conventional Rails.

Start with models, controllers, views, and normal Rails associations.

Do not introduce architectural abstractions simply to make the application appear sophisticated.

Avoid premature:

* Service objects
* Interactors
* Repositories
* Command buses
* Excessive concerns
* Policy frameworks
* Serializer frameworks

Extract logic only when existing code becomes complex enough to justify it.

Priorities:

* Readable code
* Strong naming
* Small methods
* Sensible validations
* Database constraints and indexes
* Secure parameter handling
* Ownership scoping
* N+1 awareness
* Maintainable tests
* Useful validation and empty states

## Frontend

JobFlow is primarily server-rendered Rails.

Current frontend stack:

* ERB
* Tailwind CSS

Do not introduce JavaScript, Stimulus, frontend frameworks, npm dependencies, or a new JavaScript build system unless explicitly requested.

The UI should eventually resemble modern small-business software with:

* Sidebar navigation
* Dashboard cards
* Clean tables
* Status badges
* Consistent forms
* Responsive layouts
* Empty states
* Clear validation errors
* Destructive-action confirmation

Avoid excessive animation or visual complexity.

## API

After the primary web workflow works, expose a small JSON API such as:

* GET /api/v1/jobs
* GET /api/v1/jobs/:id

Do not make the application API-first.

## Planned Milestones

### Milestone 1 — Foundation

* Authentication
* Registration
* Customer CRUD
* Job CRUD
* Ownership scoping

Completed.

### Milestone 2 — Estimates

* Estimate model
* Estimate line items
* Nested line items
* Estimate totals
* Estimate create/show/edit/update
* Estimate lifecycle actions

In progress.

### Milestone 3 — Change Orders

* ChangeOrder model
* ChangeOrderLineItem model
* Approval workflow
* Contract-value calculations

### Milestone 4 — Dashboard

Metrics including:

* Active Jobs
* Pending Estimates
* Pending Change Orders
* Active Contract Value

### Milestone 5 — Job Search and Filtering

* Text search
* Status filter
* Customer filter

Prefer server-side Rails filtering.

### Milestone 6 — Documentation Uploads

Use Active Storage for Job and Change Order files and photos.

### Milestone 7 — JSON API

Expose selected Job information.

### Milestone 8 — Demo and UI Polish

* Realistic seed data
* Application-wide navigation
* Strong Job detail page
* Consistent styling
* Empty states
* Validation presentation

### Milestone 9 — Portfolio Delivery

* Public GitHub repository
* Strong README
* Local setup instructions
* Automated tests
* Live demo if practical
* 4–6 screenshots
* Clean commit history

## Explicitly Out of Scope

Do not introduce these unless the core application is complete and the decision is made explicitly:

* Payments
* Invoicing
* QuickBooks
* Payroll
* Employee scheduling
* Timesheets
* Inventory
* Customer portal
* SMS/email workflows
* Multi-tenant organizations
* Complex role/permission systems
* Mobile apps
* AI features
* Accounting
* Estimate revision/versioning
* Chat
