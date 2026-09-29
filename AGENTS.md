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

- Inspect the relevant existing code before editing.
- Follow the conventions already used in this repository.
- Prefer small, focused changes and the smallest reasonable diff.
- Do not refactor unrelated code.
- Preserve existing user changes, including modified and untracked files.
- Do not modify unrelated files.
- Do not add gems, frontend packages, JavaScript dependencies, or other production dependencies without explicit approval.
- Do not stage, commit, push, reset, clean, discard, or otherwise alter Git history unless explicitly asked.

For normal feature work, bug fixes, tests, and UI changes, proceed directly from inspection to implementation.

Only stop before editing when:

- the requested behavior is materially ambiguous,
- different approaches would create meaningfully different product behavior,
- the change requires a new dependency or architectural pattern,
- the request conflicts with existing project conventions,
- unexpected working-tree changes could be overwritten,
- or the requested change appears unsafe or incorrect.

Otherwise: inspect, implement, test, review the diff, and report the result.

## Rails

- Prefer conventional Rails patterns over custom abstractions.
- Use Rails generators when appropriate, but inspect generated output and keep only what is needed.
- Use `bin/rails` for Rails commands when available.
- Do not edit `db/schema.rb` manually; use migrations.
- Keep controllers focused and models responsible for appropriate domain behavior.
- Avoid service objects, concerns, presenters, policies, state machines, and similar abstractions unless clearly justified or explicitly requested.
- Follow the existing authentication, routing, ownership, naming, and authorization patterns.
- Do not add redundant ownership columns when ownership already exists through associations.
- Do not persist derived values unless explicitly requested.

## Testing

- Use Minitest and the existing test style.
- Add or update tests when behavior changes.
- Run the narrowest relevant test first, then the full suite when appropriate.
- Diagnose failing tests before changing additional code.
- Do not change application behavior merely to satisfy an incorrect or stale test.
- For intentional UI changes, update presentation-specific assertions instead of restoring obsolete markup.
- Preserve ownership and security coverage.

## Frontend

- Use the existing ERB and Tailwind CSS approach.
- Preserve the current JobFlow design language.
- Do not introduce JavaScript frameworks, Stimulus, npm packages, or a new JavaScript build system unless explicitly requested.
- Prefer server-rendered Rails solutions.
- Do not broadly redesign unrelated screens during a focused ticket.
- Do not extract helpers, partials, builders, or components solely to remove minor repetition.

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

The user reviews the diff before committing. Do not require a separate pre-implementation approval step for routine work.

## Commit Messages

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

Do not use vague messages like `updates`, `changes`, `fix stuff`, or `misc changes`.
Do not push unless explicitly asked.