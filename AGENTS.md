# JobFlow Codex Instructions

## Project

JobFlow is a personal Ruby on Rails application.

Primary stack:

* Ruby on Rails
* PostgreSQL
* ERB
* Tailwind CSS
* Minitest
* Capybara
* Git

Do not assume patterns, libraries, architecture, or conventions from unrelated Rails projects.

## Working Style

* Work incrementally. Prefer small, focused changes over large rewrites.
* Inspect the relevant existing code before editing.
* Follow the conventions already used in this repository.
* Prefer the smallest reasonable diff that solves the problem.
* Do not refactor unrelated code while completing a task.
* Preserve existing user changes, including modified and untracked files.
* Check `git status` before making substantial changes when relevant.
* Do not stage, commit, push, reset, clean, or discard Git changes unless explicitly asked.
* Do not modify files unrelated to the requested task.
* Do not add gems, frontend packages, or other production dependencies without asking first.

## Rails

* Prefer conventional Rails patterns over custom abstractions unless there is a clear reason otherwise.
* Use Rails generators when appropriate, but inspect generated output and keep only what is needed.
* Use `bin/rails` for Rails commands when available.
* Do not edit `db/schema.rb` manually. Change the schema through migrations.
* Keep controllers focused and models appropriately scoped to domain behavior.
* Avoid introducing service objects, concerns, or other abstractions unless the complexity justifies them.
* Follow the authentication, authorization, routing, ownership, and naming patterns already present in JobFlow.

## Testing

* Use Minitest and the existing test style in the repository.
* Add or update tests when behavior changes.
* Run the narrowest relevant test first.
* Prefer targeted commands such as:

  `bin/rails test test/models/example_test.rb`

  before running the full suite.
* If a test fails, diagnose the failure before making additional changes.
* Do not change application behavior merely to make an incorrect test pass.
* Clearly distinguish failures caused by the current change from pre-existing failures.

## Frontend

* Follow the frontend approach already present in JobFlow.
* Do not introduce JavaScript frameworks, Stimulus controllers, npm packages, or a new JavaScript build system unless explicitly requested.
* Prefer server-rendered Rails solutions when they fit the existing application.

## Review

After implementing a meaningful change:

1. Run the relevant tests.
2. Inspect `git diff` and `git status`.
3. Review your own changes for unnecessary edits or regressions.
4. Summarize:

   * what changed,
   * which files changed,
   * which tests were run,
   * whether they passed,
   * anything the user should review carefully.
5. Do not commit the changes.

## Explanations

* When working with unfamiliar or non-obvious code, explain the important Rails or programming concepts involved.
* If there are multiple reasonable approaches, briefly explain the tradeoff before choosing one.
* Do not generate large amounts of code when a smaller implementation will work.
* When a task is non-trivial, inspect the relevant code and state the implementation approach before making broad changes.

## Commit Messages

Do not create commits unless explicitly asked.

When asked to create a commit, use concise Conventional Commit-style messages that describe the actual change:

- `feat:` new application behavior
- `fix:` bug fixes
- `test:` test-only changes
- `refactor:` behavior-preserving restructuring
- `docs:` documentation-only changes
- `chore:` tooling, configuration, or repository maintenance

Examples:

- `feat: add estimate management`
- `feat: connect customers and jobs`
- `fix: scope jobs to current user`
- `test: cover estimate ownership`
- `docs: add project overview`

Do not use vague messages such as `updates`, `changes`, `fix stuff`, or `address feedback`.