# JobFlow Codex Instructions

## Project

JobFlow is a personal Ruby on Rails application.

Primary stack:

- Ruby on Rails
- PostgreSQL
- ERB
- Tailwind CSS
- Minitest
- Capybara
- Git

Do not assume patterns, libraries, architecture, or conventions from unrelated Rails projects.

## Working Style

- Inspect the repository as needed before making changes.
- Use the files, tests, routes, schema, and configuration already available locally; do not ask the user to provide repository code you can inspect yourself.
- Proceed directly from inspection to implementation for normal feature work, bug fixes, tests, and UI changes.
- You are authorized to make the non-destructive file changes and run the development commands necessary to complete the requested ticket without asking for approval first.
- Do not stop to announce a plan, list files you intend to inspect, or ask permission to make routine changes.
- Follow existing repository conventions and prefer the smallest focused diff that solves the task.
- Preserve existing user changes and do not modify unrelated files.
- Do not refactor unrelated code.
- Do not add gems, frontend packages, JavaScript dependencies, or other production dependencies without explicit approval.
- Do not stage, commit, push, reset, clean, discard, or otherwise alter Git history unless explicitly asked.

Only stop before implementation when:

- the requested behavior is materially ambiguous,
- reasonable approaches would produce meaningfully different product behavior,
- a new dependency or architectural pattern is required,
- the request conflicts with existing project conventions,
- unexpected working-tree changes could be overwritten,
- credentials, elevated privileges, or explicit runtime authorization are required,
- or the requested change appears unsafe or incorrect.

Otherwise: inspect, implement, verify, self-review, and report.

## Rails

- Prefer conventional Rails patterns over custom abstractions.
- Use Rails generators when appropriate, but inspect generated output and keep only what is needed.
- Use `bin/rails` for Rails commands when available.
- Do not edit `db/schema.rb` manually; use migrations.
- Keep controllers focused and models responsible for appropriate domain behavior.
- Avoid service objects, concerns, presenters, policies, state machines, and similar abstractions unless clearly justified or explicitly requested.
- Follow the existing authentication, routing, ownership, naming, and authorization patterns.
- Do not add redundant ownership columns when ownership already exists through associations.
- Do not persist values that are intentionally derived from existing data unless explicitly requested.
- Avoid obvious N+1 queries, but do not introduce unnecessary optimization infrastructure.

## Testing and Verification

- Use Minitest and the existing test style.
- Add or update tests when behavior changes.
- Run the narrowest relevant test first, then the full Rails suite when appropriate.
- You are authorized to run ordinary non-destructive verification commands without asking, including:
  - targeted Rails tests,
  - the full Rails suite,
  - `git diff --check`,
  - repository searches,
  - lightweight local assertions or scripts when relevant.
- If a normal verification command fails because of a sandbox or environment limitation, use an available safe fallback or retry mechanism without asking when permitted.
- Only ask the user when the runtime itself requires explicit authorization, elevated privileges, credentials, or access that cannot be obtained automatically.
- Diagnose test failures before making additional changes.
- Do not change application behavior merely to satisfy an incorrect or stale test.
- For intentional UI changes, update presentation-specific assertions rather than restoring obsolete markup.
- Preserve ownership and security coverage.

## Frontend

- Use the existing ERB and Tailwind CSS approach.
- Preserve the current JobFlow design language.
- Prefer server-rendered Rails solutions.
- Do not introduce JavaScript frameworks, Stimulus, npm packages, or a new JavaScript build system unless explicitly requested.
- When JavaScript or Stimulus is explicitly approved for a ticket, use the smallest conventional implementation.
- Do not broadly redesign unrelated screens during a focused ticket.
- Do not extract helpers, partials, builders, or components solely to eliminate minor repetition.

## Security and Ownership

- Keep user-owned data scoped through the authenticated user using existing ownership patterns.
- Do not trust submitted foreign keys to establish ownership.
- Load nested resources through their owned parent where appropriate.
- Preserve protection against cross-user URLs and foreign nested record IDs.
- Do not expose protected lifecycle fields through generic form parameters unless explicitly required.

## Review

After a meaningful change:

1. Run relevant targeted tests.
2. Run the full Rails suite when appropriate.
3. Run `git diff --check`.
4. Inspect `git diff` and `git status`.
5. Self-review for unnecessary edits, regressions, ownership issues, and avoidable queries.
6. Report:
   - what changed,
   - exact files changed,
   - tests run and results,
   - important tradeoffs or issues.

The user reviews the final diff before committing.

Do not ask for a separate pre-implementation approval step for routine work.

## Commits

Do not create commits unless explicitly asked.

When asked to commit, review the final diff and test results first.

Use concise Conventional Commit-style messages:

- `feat:` new application behavior
- `fix:` bug fixes
- `test:` test-only changes
- `refactor:` behavior-preserving restructuring
- `docs:` documentation-only changes
- `chore:` tooling, configuration, or repository maintenance

Examples:

- `feat: add estimate management`
- `feat: add dashboard metrics`
- `fix: scope jobs to current user`
- `test: cover estimate ownership`
- `docs: add project overview`

Do not use vague messages such as `updates`, `changes`, `fix stuff`, or `misc changes`.

Do not push unless explicitly asked.