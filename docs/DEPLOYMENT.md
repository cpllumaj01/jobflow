# Production deployment checklist

JobFlow has not been deployed by this preparation ticket. Select the hosting target before using the generated deployment template.

## Existing tooling

- `Dockerfile`: Ruby 4.0.7, multi-stage build, PostgreSQL client and libvips, Bootsnap, production asset precompilation, non-root runtime, and Thruster on port 80. Development/test gem groups are excluded.
- `bin/docker-entrypoint`: runs `bin/rails db:prepare` before the default Rails server command.
- `config/deploy.yml`, `.kamal/secrets`, and `bin/kamal`: generated Kamal configuration. The private IP, local registry, image name, and commented proxy/accessories are placeholders, not a deployable environment. The commented MySQL example is not suitable for this PostgreSQL app.
- `config/puma.rb`, `bin/jobs`, `config/queue.yml`, `config/recurring.yml`: web and Solid Queue worker configuration.
- `.github/workflows/ci.yml`: tests, lint, and security checks; it does not deploy or build the production image.

## Database and migrations

Production uses four PostgreSQL databases: `jobflow_production`, `jobflow_production_cache`, `jobflow_production_queue`, and `jobflow_production_cable`. Solid Cache, Queue, and Cable require their own schemas in this configuration.

The defaults use the `jobflow` role, `JOBFLOW_DATABASE_PASSWORD`, and a local socket. Containers normally need explicit remote connections. Supply **all four** connection URLs, including the host, role, password, database, and any provider-required TLS options:

- `DATABASE_URL` for primary application data
- `CACHE_DATABASE_URL` for Solid Cache
- `QUEUE_DATABASE_URL` for Solid Queue
- `CABLE_DATABASE_URL` for Solid Cable

A primary URL does not configure the other three connections. `DB_HOST` is not read by the current database configuration. Do not point all four URLs at the same database without deliberately revising and validating the multi-database design.

Provision databases and permissions before starting the application when the hosted role cannot create databases. Run with runtime secrets and production connection settings:

```sh
RAILS_ENV=production bin/rails db:prepare
RAILS_ENV=production bin/rails db:migrate:status
```

`db:prepare` loads the checked-in schemas for new databases and migrates existing ones. Production configurations set `seeds: false`, preventing automatic demo seeding on first boot. Explicit `db:seed` still aborts in production; the existing guard is unchanged. Development seeds continue to work.

The default container entrypoint prepares databases automatically. For a hosting release phase or multiple replicas, decide which single process performs preparation before serving traffic, and start workers only afterward. Back up databases before upgrades and verify restore procedures.

## Secrets and runtime settings

| Setting | Requirement |
| --- | --- |
| `RAILS_ENV=production` | Already set by the Dockerfile. |
| `RAILS_MASTER_KEY` | Matching decryption key for the deployed Rails credentials. The Kamal template obtains it from local `config/master.key`; keep keys in the host's secret manager, never in the image or Git. Environment-specific credentials require their matching key. |
| `SECRET_KEY_BASE` | Rails normally obtains this from encrypted credentials. Alternatively inject a strong, stable runtime secret. It does not replace keys needed to decrypt other credentials. Changing it invalidates signed sessions/tokens. |
| Database URLs or `JOBFLOW_DATABASE_PASSWORD` | See database configuration above; use the provider's secret store. |
| `SECRET_KEY_BASE_DUMMY` | Build-only, used for asset compilation. Never set it on a deployed runtime. |
| `RAILS_LOG_LEVEL` | Optional; defaults to `info`. Logs go to stdout with request IDs; `/up` requests are silenced. Arrange log retention at the host. |
| `SOLID_QUEUE_IN_PUMA` | Kamal sets it to true for one-server operation. Otherwise run `bin/jobs` as a separate worker. Omit this variable to disable the plugin; the string `false` is still truthy in the current Puma configuration. |
| `PORT`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `JOB_CONCURRENCY` | Optional process tuning; size database connections for both web and workers. |
| `KAMAL_REGISTRY_PASSWORD` | Only needed if the selected container registry requires authentication; configure its reference in Kamal. |

No storage credentials are currently needed for Disk storage. No SMTP environment variables are wired into the application yet. Never paste secret values into deployment files, command examples, or logs.

## Persistent attachments

Production currently uses Active Storage `:local`, rooted at `storage/` (`/rails/storage` in the container). Kamal declares the persistent `jobflow_storage:/rails/storage` volume. Keep it mounted, writable by the container's UID 1000, and backed up alongside the database. A volume survives container replacement but does not provide off-host backup or multi-host replication.

For another host, choose either:

1. A persistent disk mounted at `/rails/storage`, shared with workers that process attachments; suitable for a single-host deployment.
2. An approved object-storage service, with the required adapter dependency and credentials configured in a subsequent ticket; suitable for ephemeral or multi-host deployments.

Do not deploy the current Disk configuration onto an ephemeral filesystem. No cloud provider has been selected or added.

## Production demo data

Deploy the code and prepare the production database normally first. Normal production `db:seed` remains blocked, and `db:prepare` still skips seeds. Demo bootstrap is a separate manual operation; do not add it to startup or deployment commands.

1. Confirm that `demo@jobflow.test` is the intended demonstration account. Every bootstrap replaces that account's customers and all nested jobs, estimates, change orders, and attachments, and resets its password. Other users are untouched. Back up the database and storage before running it.
2. Supply `DEMO_PASSWORD` through the deployed service's secret environment (Railway service Variables), using a generated password of 16–72 bytes. There is no production default. Do not place the value in source, command arguments, logs, or shell history. The task never prints it. The password is intentionally used for demo sign-in; never reuse an administrator or personal password.
3. Confirm that the running web service has its persistent volume mounted at `/rails/storage`, writable by UID 1000. Production currently uses Active Storage Disk. Run this **inside that running service's container**, through a Railway SSH session, from `/rails`:

   ```sh
   RAILS_ENV=production ALLOW_PRODUCTION_DEMO_BOOTSTRAP=true bin/rails demo:bootstrap
   ```

   `DEMO_PASSWORD` must already be available in the container environment. Keep the opt-in on this one command rather than setting it permanently. Do not use a local `railway run`, a build step, or a deployment pre-command: the scope attachment must be written onto the same persistent disk used by the web process.
4. Sign in as `demo@jobflow.test` with the supplied password. Check the dashboard, kitchen contract value ($25,960), and download `kitchen-renovation-scope.txt`. Remove the temporary `DEMO_PASSWORD` variable after use if desired; the account retains only its password digest. Supply it again on the next refresh.

The shared loader creates four fictional customers, six jobs covering every job status, six estimates, four kitchen change orders covering every change-order status, and one text attachment. Reruns replace this same account's dataset rather than adding duplicates. Record IDs change, and dates remain relative to the day of the refresh, as with local seeds. The account itself is retained.

The task rejects non-production environments, an opt-in other than `true`, and missing or unsuitable passwords before modifying records. A database transaction protects the replacement, and a PostgreSQL transaction advisory lock serializes concurrent loader runs. Database errors before commit roll back the password and replacement together. Active Storage uploads occur after commit and cannot be atomic with PostgreSQL: if a disk/upload failure occurs, correct storage and rerun the task. Replaced attachments use Active Storage's normal asynchronous purge lifecycle; keep the existing job worker running for cleanup. No unrelated blobs are globally purged by the task.

Local verification uses Rails transactional fixtures and a temporary test Disk directory, with production environment checks simulated only around task invocation. It exercises two refreshes with attachment upload callbacks, attachment downloads, password authentication, unrelated-user preservation, guard rejection, and rollback on a mid-refresh failure; it does not contact a deployed database.

## HTTPS, domain, and email prerequisites

Production enforces HTTPS and secure cookies, with HTTP `/up` exempted from redirects for health probes. Configure a TLS-terminating proxy and verify forwarded HTTPS headers. If the trusted proxy requires `config.assume_ssl`, enable it for that deployment. The Kamal TLS proxy block is still commented out. Configure the real domain and an appropriate `config.hosts` allowlist before public exposure; host restrictions are currently unset.

Password reset calls `deliver_later`, so it requires working Solid Queue databases and a running worker as well as mail delivery. Rails currently uses its default SMTP transport (localhost:25) with no configured provider. Production mail links still use `example.com`, and `ApplicationMailer` uses `from@example.com`.

Before enabling public password reset, configure an SMTP/provider endpoint, credentials, TLS/authentication settings, verified sender, and production URL host/protocol. The commented SMTP credentials example in `production.rb` is not active configuration. No provider is included in this ticket. Sign-in itself does not require email delivery; password reset will not work until these prerequisites are met.

## Health, build, and verification

`GET /up` is the existing Rails boot health check, not a database/storage/SMTP readiness probe. Configure those service checks separately at the host if needed.

Build assets without production secrets:

```sh
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 BUNDLE_WITHOUT=development:test bin/rails assets:precompile
```

Troubleshooting: Normal Rails development picks up Stimulus/controller changes after a browser refresh; asset precompilation and Rails restarts are not routine development steps. Only if you intentionally ran a local production `assets:precompile` and left `public/assets/.manifest.json` behind, run `bin/rails assets:clobber` and refresh the browser to recover from stale compiled assets. This is an exceptional recovery step, not part of the normal development workflow.

When Docker is available:

```sh
docker build -t jobflow .
```

Do not expose the application publicly before supplying database connections, runtime secrets, persistent storage, and TLS. Configure production mail delivery before relying on password-reset functionality.

Local audit results:

- Production asset build passed with development/test gem groups excluded.
- An isolated temporary source copy without real encrypted credentials booted using disposable secrets and four uniquely named local PostgreSQL databases.
- Fresh and repeated production `db:prepare` passed; primary tables contained no demo users. The explicit production seed guard rejected seeding.
- Production eager loading, HTTP `/up` (200), HTTPS redirect, and HTTPS sign-in rendering (200) passed.
- Full Rails suite passed. The local host lacks libvips; the Dockerfile installs it. No image variants are used by the current attachment UI.
- Docker image build/runtime verification remains outstanding: Docker Desktop WSL integration was unavailable. Repeat the image build, migrations, health, persistence, and mail checks on the chosen host.

## Repository hygiene

The audit found no tracked plaintext credential keys, environment files, uploaded files, or database dumps. Tracked `config/credentials.yml.enc` is encrypted; `.kamal/secrets` contains a key-file reference, not a literal secret. Git and Docker ignore local environment files, keys (including environment-specific credential keys), uploads, logs, temporary files, root database exports, and `.aws/`.

This is a working-tree/configuration audit, not a complete Git-history secret scan. Keep any differently located exports or credentials out of both version control and Docker build contexts.
