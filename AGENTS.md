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
- Use the files, tests, routes, schema, configuration, fixtures, migrations, and repository state already available locally; do not ask the user to provide repository code you can inspect yourself.
- Proceed directly from inspection to implementation for normal feature work, bug fixes, tests, and UI changes.
- You are authorized to make the non-destructive file changes and run the development commands necessary to complete the requested ticket without asking for conversational approval first.
- Do not stop to announce a plan, list files you intend to inspect, or ask permission to make routine changes unless the user explicitly requested a plan before implementation.
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
- required credentials are unavailable,
- elevated operating-system privileges are required and cannot be handled through the runtime's normal approval mechanism,
- no safe execution path remains after permitted sandbox or environment fallbacks,
- or the requested change appears unsafe or incorrect.

Otherwise: inspect, implement, verify, self-review, and report.

## Sandbox and Runtime Authorization

- Sandbox, host-mount, or environment failures are not reasons to ask the user conversationally for permission.
- Repository inspection, searches, file reads, non-destructive edits, tests, and verification commands are routine authorized work.
- If normal repository access fails because of a sandbox, host-mount, or environment problem, automatically attempt an available safe non-destructive fallback.
- Do not ask questions such as:
  - "May I inspect the repository outside the sandbox?"
  - "May I inspect the existing implementation outside the sandbox?"
  - "May I inspect the existing tests outside the sandbox?"
  - "May I run the tests outside the sandbox?"
  - "May I retry this outside the sandbox?"
- If the runtime requires approval for an otherwise authorized non-destructive action, use the runtime approval flow directly and continue automatically when permitted by the configured approval policy.
- Treat inspection of existing application code, tests, routes, schema, migrations, configuration, fixtures, Git diff, Git status, and similar repository state as routine authorized work.
- Treat targeted tests, the full Rails suite, repository searches, `git diff --check`, and other ordinary non-destructive verification commands as routine authorized work.
- Do not stop merely because an action must use an approved runtime fallback when the normal sandbox is unavailable.
- Only stop for user guidance when:
  - no safe execution path remains,
  - required credentials are unavailable,
  - elevated operating-system privileges cannot be handled through the runtime,
  - or proceeding could modify or destroy data outside the requested scope.
- Never bypass or attempt to defeat an actual runtime security restriction. Use the runtime's provided approval or fallback mechanism when one exists.

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
- Prefer explicit Rails behavior over custom framework-like abstractions.
- Reuse existing model methods and associations instead of duplicating domain calculations in views or controllers.

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
- If a verification command fails because of a sandbox, host-mount, or environment limitation, automatically use an available safe fallback or retry mechanism.
- If the runtime requires approval for such a fallback, use the runtime approval flow directly and continue automatically when permitted by the configured approval policy.
- Do not ask whether you may inspect test files or run tests outside a broken sandbox when the runtime can handle approval directly.
- Diagnose test failures before making additional changes.
- Do not change application behavior merely to satisfy an incorrect or stale test.
- For intentional UI changes, update presentation-specific assertions rather than restoring obsolete markup.
- Preserve ownership and security coverage.
- Prefer tests that verify behavior rather than unnecessarily coupling to implementation details or incidental markup.
- Do not add redundant tests that merely duplicate existing coverage without adding meaningful confidence.

## Frontend

- Use the existing ERB and Tailwind CSS approach.
- Preserve the current JobFlow design language.
- Prefer server-rendered Rails solutions.
- Do not introduce JavaScript frameworks, Stimulus, npm packages, or a new JavaScript build system unless explicitly requested or already approved for the ticket.
- When JavaScript or Stimulus is explicitly approved for a ticket, use the smallest conventional implementation.
- Do not broadly redesign unrelated screens during a focused ticket.
- Do not extract helpers, partials, builders, or components solely to eliminate minor repetition.
- Prefer semantic HTML and native browser behavior before adding custom JavaScript.

### Stimulus

When Stimulus is appropriate or explicitly requested:

- Prefer declarative `data-action` bindings over manually attaching DOM event listeners.
- Use Stimulus targets for DOM elements the controller needs to reference.
- Use Stimulus values for configurable controller settings such as debounce delays instead of unexplained magic numbers.
- Use `connect()` only when initialization work is actually required.
- Use `disconnect()` to clean up timers, observers, subscriptions, global listeners, or other side effects created by the controller.
- Keep controllers small and focused on UI behavior.
- Keep business and domain logic in Rails models or controllers where appropriate.
- Prefer native browser APIs such as `requestSubmit()` rather than manually reproducing browser behavior.
- Do not add JavaScript for behavior that is already handled cleanly by server-rendered Rails.
- Avoid manual DOM querying when a Stimulus target expresses the relationship more clearly.
- Avoid manual event-listener setup when `data-action` can express the behavior declaratively.

## Security and Ownership

- Keep user-owned data scoped through the authenticated user using existing ownership patterns.
- Do not trust submitted foreign keys to establish ownership.
- Load nested resources through their owned parent where appropriate.
- Preserve protection against cross-user URLs and foreign nested record IDs.
- Do not expose protected lifecycle fields through generic form parameters unless explicitly required.
- Prefer ownership scoping through existing associations rather than adding redundant user references.
- Add or preserve tests for cross-user access when modifying owned resources or nested routes.

## Scope and Architecture

- Keep each ticket focused on the requested behavior.
- Do not begin adjacent roadmap work unless explicitly requested.
- Do not introduce abstractions solely because they might be useful later.
- Prefer implementing the current requirement cleanly over designing speculative infrastructure.
- Reuse existing conventions before creating a new application pattern.
- If a new pattern would materially affect future architecture, stop and ask before introducing it.

## Review

After a meaningful change:

1. Run relevant targeted tests.
2. Run the full Rails suite when appropriate.
3. Run `git diff --check`.
4. Inspect the final diff.
5. Inspect `git status --short`.
6. Self-review for:
   - unnecessary edits,
   - regressions,
   - ownership issues,
   - security issues,
   - avoidable queries,
   - duplicated domain logic,
   - unnecessary abstractions.
7. Report:
   - what changed,
   - exact files changed,
   - tests run and results,
   - important tradeoffs or issues.

The user reviews the final diff before committing.

Do not ask for a separate pre-implementation approval step for routine work unless the user explicitly requested one for that ticket.

## Commits

Do not create commits unless explicitly asked.

When asked to commit:

- review the final diff and test results first,
- include only files belonging to the intended change,
- use a concise Conventional Commit-style message.

Commit types:

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

Do not use vague messages such as:

- `updates`
- `changes`
- `fix stuff`
- `misc changes`

Do not push unless explicitly asked.
