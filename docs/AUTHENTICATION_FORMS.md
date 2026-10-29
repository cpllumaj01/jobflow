# Authentication forms and password usability

## Issue #66 audit

The rendered forms were inspected before implementation, including their input types, names, IDs, labels, autocomplete hints, and form boundaries. Rails 8.1 generates field IDs by default in this application. The original sign-in page already had a single form containing correctly labeled `email_address` (`type="email"`, `autocomplete="username"`) and `password` (`type="password"`, `autocomplete="current-password"`) inputs. No duplicate IDs, swapped field types, nested forms, or password-to-email assignments were found there.

| Form | Finding and change |
| --- | --- |
| Sign in | Existing field semantics retained; added visibility control. |
| Registration | Email used `autocomplete="email"`, which describes contact information rather than the login identifier. Changed it to `username`; both password fields retain `new-password` and distinct Rails-generated IDs. Added independent visibility controls. |
| Reset request | Existing labeled email input with `username` retained. |
| Reset password | Both password fields already used `new-password`, but the form had no username to identify which saved account to update. Added a hidden `email_address` input with `username`, populated from the reset-token owner, and visibility controls. |
| Start 2FA setup | Current-password-only form had no username. Added the authenticated account's hidden username, an explicit `setup_password` ID with its matching label, and a visibility control. |
| Confirm 2FA setup | Existing labeled text input, `one-time-code`, numeric input mode, and six-digit constraint retained. |
| Regenerate recovery codes / disable 2FA | Already separate forms with distinct password/code IDs and matching labels. Added a hidden username to each, with distinct IDs, and independent visibility controls. |
| Sign-in 2FA challenge | Existing text input and `one-time-code` retained. Combined authenticator/recovery-code inputs allow letters and hyphens; they are never password inputs. |

Missing account context and registration's contact-email hint are likely contributors to ambiguous password-manager pairing, especially with multiple saved accounts. They do not prove the cause of the reported production misfill: the original sign-in markup was already correct, and the affected saved credentials/browser profile are unavailable here. Actual saved-credential pairing remains a manual browser check.

Hidden usernames contain real account context, following [Chromium's password-form guidance](https://www.chromium.org/developers/design-documents/create-amazing-password-forms/). They are hints for password managers; controllers continue to establish identity from the authenticated session or validated reset token and ignore the submitted email on these actions. [Apple's AutoFill guidance](https://developer.apple.com/documentation/security/enabling-password-autofill-on-an-html-input-element) likewise recommends `type="email"` with `autocomplete="username"` when email is the login identifier. No autocomplete suppression, dummy fields, or browser-specific workarounds were added.

## Visibility and validation

All eight password inputs use one ERB partial and one Stimulus controller. Each eye button has `type="button"`, an accessible action label, an `aria-controls` reference to its input, and a 44-pixel minimum touch target. Pointer activation preserves focus in an already focused input; keyboard activation retains button focus. Toggling changes the existing input's type and preserves its value, selection, name, and autocomplete hint. Each field toggles independently.

Fields start masked. Stimulus resets the visibility state on connection and before Turbo caches the page. Declarative Stimulus actions handle listener cleanup across navigation. Without JavaScript, the native masked input still works and the toggle stays hidden.

Password requirements, controller parameters, validation messages, CSRF protection, session handling, and second-factor checks are unchanged. Registration retains its submitted email and validation errors. Rails' existing behavior of rendering password inputs blank after a server validation response/redirect is preserved; passwords are not echoed into response HTML. The visibility controller never reads or writes the input's value, logs it, copies it, or puts it into browser storage.

## Password copying investigation

Application searches found no password copy/cut/paste handlers, masking replacements, password-value transformations, or assignments between email and password fields. The existing clipboard controller acts only on the displayed recovery-code list. Password hashing happens on the server through Rails' `has_secure_password`/bcrypt. A password input's dots are a browser presentation of its value, not encrypted text stored in the input; see [MDN's password-input reference](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/password).

A desktop Chrome for Testing 156.0.8078.73 probe on Linux used only disposable test text and native Ctrl+A/Ctrl+C:

- With the input masked, Copy left the previous clipboard text unchanged.
- After revealing the same input, Copy produced exactly the entered text.
- Native paste and revealed copying also preserved leading/trailing spaces in system coverage.

An unchanged clipboard can explain apparently unexpected pasted text after attempting to copy a masked password. The production report cannot be conclusively attributed to that behavior without the original browser/profile. Masked copying and password-manager clipboard behavior vary; a browser can suppress copying while masked, and an extension may manage its own clipboard. Reveal first to inspect/select/copy the actual input text using the browser's native commands. No application clipboard handling was added.

The browser checks also exposed an existing recovery-code system test that replaced `navigator.clipboard.writeText` to simulate denial and left that replacement installed. Its cleanup now restores the native method so later clipboard tests are isolated. This was test-only behavior, not a production password-copy defect.

## Verification and remaining manual checks

Integration coverage checks field types, parameter names, unique IDs, associated labels, autocomplete tokens, same-form username/password pairing, validation responses, and reset-token ownership. Chrome system coverage checks pointer/keyboard controls, unchanged values and selections, native paste/copy, registration and confirmation, reset validation/submission, repeated Turbo restoration, and the existing login/2FA flows including setup, regeneration, and disabling at a 375-pixel viewport. Desktop Chrome screenshots were visually reviewed for sign-in and registration. These checks do not exercise a real saved-password profile or verify Safari AutoFill.

Local verification completed on October 28, 2026, without retries:

- `env -u DEBUG PARALLEL_WORKERS=1 bin/rails test`: 383 tests, 4,558 assertions; no failures, errors, or skips.
- `env -u DEBUG TEST_HEADLESS=true PARALLEL_WORKERS=1 bin/rails test:system`: 31 tests, 924 assertions; no failures, errors, or skips.
- RuboCop on the four changed/new Ruby test files: no offenses. `git diff --check`: passed.

Use disposable accounts on a non-production HTTPS origin for the following checks. Record the browser/OS versions and password manager used. No production data is required.

### Chrome desktop saved credentials

1. In an isolated normal browser profile, create two test accounts with different credentials and save both. Also try Chrome's generated-password suggestion at registration; verify confirmation and successful submission.
2. Sign out, reload sign-in, and select each saved account in turn from both the email and password fields. Confirm the matching email/password pair fills, email never receives a password, and both accounts can sign in. Repeat after navigating through registration/reset and Back/Forward.
3. Reset one account's password. Confirm the password manager offers to update that account, its new credentials sign in, and the other saved account stays unchanged.
4. On account security, autofill the current password for setup, regeneration, and disabling. Verify no saved password fills an authenticator/recovery-code field and that second-factor verification is still required.
5. Test the configured extension password manager separately if one was involved in the original report. Inspect any stale/mislabeled saved entry in the isolated profile and record differences before changing it.

### Safari on iOS (required; not verified here)

1. Record the iOS/Safari version and enabled AutoFill provider. Save two disposable accounts with distinct emails/passwords. With Safari's keyboard Passwords/AutoFill UI, select each account from sign-in and verify that email and password always pair correctly. Repeat after reload, sign-out, and Back/Forward navigation.
2. Register using Safari's strong-password suggestion. Confirm both new-password fields receive the intended password and saving associates it with the submitted email. Repeat with a manually entered passphrase and a confirmation mismatch; check that the error and email remain correct, then correct and submit.
3. Open a reset link for account A, including while signed in as account B. Generate or paste a new password, reveal/hide each field independently, submit, and check that Safari updates A's saved password only. Confirm reset still requires 2FA on the next sign-in when enabled.
4. Start 2FA setup, regenerate recovery codes, and disable 2FA. Check that the correct account's current password is offered, the code fields accept the intended authenticator/recovery code rather than a saved password, and a wrong password or code is rejected.
5. With the software keyboard open, tap the eye repeatedly. Verify the icon/label updates, text and caret remain intact, focus/keyboard behavior is usable, the button never submits, and the touch target fits without horizontal scrolling. Repeat in portrait/landscape and with larger text. With VoiceOver, check field labels, Show/Hide announcements, and button activation; use Tab/Space/Return with an external keyboard if available.
6. Paste disposable text including spaces into a password field. Attempt native long-press Copy while masked and record whether it is unavailable or leaves the previous clipboard unchanged. Reveal, Select All, Copy, and paste into a temporary plain-text test destination; verify the exact text. Test the affected AutoFill provider separately and clear the disposable clipboard afterward.
7. Reveal a field, navigate to registration/reset and back several times, and confirm fields return masked and each eye toggles once. Submit after both revealing and hiding to confirm normal validation and authentication.
