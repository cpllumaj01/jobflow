# Two-factor authentication

Signed-in users can open **Account security** from the navigation. Confirm the current password, enter the setup key into a time-based authenticator app, and confirm a six-digit code. The page also provides a standard `otpauth` provisioning URI for compatible apps. Setup expires after ten minutes and does not enable 2FA until confirmed. Starting again replaces the browser's pending setup; canceling removes it. QR rendering is omitted to keep `rotp` the only new dependency. No secret is sent to another service.

Activation displays ten recovery codes once. Save them in a password manager before leaving the page. Each code replaces an authenticator code once. Account security allows regeneration or disabling with both the current password and a current authenticator code or unused recovery code. Both actions revoke other sessions and rotate the initiating session; enabling does the same. Password resets revoke sessions and preserve 2FA, so a reset alone cannot bypass the second factor.

## Encryption configuration

Development and production require all three variables:

| Variable | Purpose |
| --- | --- |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Encrypts persisted TOTP secrets using Rails Active Record Encryption. |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Configures the standard Rails encryption key set; TOTP secrets use nondeterministic encryption. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Salt for Rails encryption key derivation. |

Use three independent cryptographically random values. Keep them stable and separate from `SECRET_KEY_BASE` and `RAILS_MASTER_KEY`. The application checks for missing values at boot without printing secrets. It does not silently derive production encryption keys from other secrets. Docker asset builds can use the existing build-only `SECRET_KEY_BASE_DUMMY`; never set it at runtime.

For a **new** local configuration, this command writes generated values directly to an ignored, owner-readable `.env.local`, without printing keys or putting their values into shell history. It refuses to overwrite an existing file:

```sh
ruby -rsecurerandom -e 'File.open(".env.local", File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| %w[PRIMARY_KEY DETERMINISTIC_KEY KEY_DERIVATION_SALT].each { |name| f.puts "ACTIVE_RECORD_ENCRYPTION_#{name}=#{SecureRandom.hex(32)}" } }'
```

If `.env.local` already exists, preserve it and securely add only missing variables using a local editor/password manager. Dotenv loads `.env.local` in development. Never commit environment files, keys, or plaintext credentials. Do not regenerate keys after enabling 2FA: existing ciphertext would become unreadable. Keep an access-controlled backup of keys with your database recovery material. Consult Rails' encryption key-rotation procedure before deliberately rotating them.

Tests use fresh in-memory random encryption keys when variables are absent. This is for disposable test databases only; no test key is committed. Production subprocess tests explicitly supply disposable keys. To work with persistent encrypted records in a test database across separate processes, supply stable test-only values through `.env.test.local` or the environment, never production keys.

After installing the updated bundle and configuring keys, run:

```sh
bin/rails db:migrate
```

For production, inject all three values through the host's secret manager on web, worker, and migration processes, then migrate before serving traffic. Do not put them in the Docker image, deployment YAML, command arguments, logs, or Git. Losing the primary key or derivation salt prevents decrypting authenticator secrets. Database encryption does not protect against a compromised application process holding both ciphertext and keys.

## Authentication and storage

- The existing password-only flow is preserved for users without 2FA. Registration continues to use Rails' database-backed sessions.
- For users with 2FA, a valid password rotates the Rails browser session and removes any previous authenticated session from that browser. Only a signed, five-minute challenge token and a validated return destination are kept in the encrypted Rails session cookie. No database `Session` record is created and no `Current.session` is assigned until the second factor succeeds.
- Rails' purpose-bound tokens contain a SHA-256 fingerprint of the password and second-factor state, rather than secrets themselves, plus a persisted cancellation version. Tokens are revalidated under a user-row lock before verification and session creation. Successful verification, password changes, enabling/disabling 2FA, and recovery-code regeneration invalidate old challenges. Canceling a valid challenge increments the version under the same lock, so a saved pre-cancel cookie cannot revive it. Completing or canceling a challenge also invalidates other outstanding challenges for that account; those browsers can restart sign-in. Stale cancellation requests cannot invalidate newer challenges or revoke completed login sessions.
- TOTP uses `rotp` 6.3, six-digit codes with 30-second steps and 15 seconds of clock-skew tolerance in either direction. The last accepted step is persisted, preventing reuse. If a code has already been used for setup or sign-in, wait for a new code or use a recovery code.
- Both `users.otp_secret` and the unconfirmed `users.otp_setup_secret` use nondeterministic Active Record Encryption. Only the active secret enables 2FA. The browser session contains an expiring setup token bound to the initiating database session and the pending secret’s fingerprint, never the plaintext secret. Confirmation and cancellation clear the pending secret; restarting replaces it and invalidates previous setup tokens. Expired setup is rejected and its browser state cleared when submitted; an abandoned encrypted pending secret remains inert until replaced or canceled.
- Recovery codes contain 128 bits of randomness each. Only SHA-256 digests are persisted; no plaintext list is stored in the database, cookie, or flash. User-row locking and a transaction make consumption single-use under concurrency. Regeneration invalidates every old code.
- Login verifies the password under the existing email/IP rate limits. Second-factor verification and account-security mutations share a ten-attempt/five-minute account limit, with separate IP limits. All authentication-related throttles, including password-reset requests, use a small counter adapter through Rails' public `rate_limit store:` option because Rails normally skips enforcement when a counter returns `nil`. An unavailable counter rejects the request with HTTP 429 before password authentication, factor consumption, delivery, or account-security changes; raised cache errors also stop the request. Production uses the existing shared Solid Cache store, and local development uses its existing memory cache. Cache availability is therefore required for throttled authentication actions. Tests use an isolated memory store for controller counters and clear it between tests; the global test cache remains a null cache.
- Management actions require the authenticated user, preserve Rails CSRF protections, and ignore submitted user IDs and protected model fields. Security pages use `Cache-Control: no-store`, disable Turbo snapshots, and suppress referrers. Passwords, verification codes, recovery-code fields, and secrets are filtered from Rails logs and model inspection. Provisioning URIs are rendered as text, never placed in HTTP URLs or external images.

There are no trusted devices, external identity providers, or password-only 2FA reset routes. A user who loses both their authenticator and all recovery codes cannot disable 2FA through password reset. No administrative recovery workflow is introduced by this ticket.
