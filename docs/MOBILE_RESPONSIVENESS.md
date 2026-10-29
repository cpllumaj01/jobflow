# Mobile responsiveness — issue #76

## Findings and changes

The application already declares `width=device-width,initial-scale=1`. That declaration remains intact, with no zoom limits or document-level overflow suppression. Sign-in, password, and 2FA inputs used 14px text, including autofocus fields: a likely contributor to the reported initial zoom on iOS Safari. Editable controls now use at least 16px on small viewports or devices with a coarse pointer, including tablets and landscape orientations. Larger browser text settings can still increase that size. Chrome emulation cannot confirm Safari's focus-zoom behavior.

Authenticated navigation uses a disclosure below 768px and the existing horizontal links at larger widths. The Menu button exposes its controlled navigation and expanded state. Native Tab/Shift+Tab, Enter/Space, Escape, leaving the navigation, resizing, Turbo visits/restoration, and sign-out are supported. Escape returns focus to Menu; breakpoint changes move focus out of controls becoming hidden. Without JavaScript the navigation links remain available.

The expanded audit reproduced a wrapping “In progress” badge at 320px. Shared status pills now remain on one line without shrinking; surrounding content can wrap. Job and estimate date fields have explicit maximum widths, neutralized native appearance, and shrinkable grid parents, retaining native date/datetime input types and pickers. The iOS-native rendering still requires physical-browser verification.

The 320px 2FA audit also found clipped submit labels and short cancel controls. The affected submit inputs are now wrapping submit buttons, and cancel controls have 44px minimum heights. Existing table regions retain local, keyboard-accessible horizontal scrolling. Other audited screens needed no structural redesign.

The repository search found one unnecessary device-model reference: the unverified Safari manual-test heading in `AUTHENTICATION_FORMS.md`, now generalized to Safari on iOS. Historical test results were retained.

## Automated verification

Browser checks use headless Chrome for Testing 156.0.8078.73 on Linux. CSS widths are 320, 375, 390, 430, 768, and 1400px. Responsive layout tests use CDP mobile viewport and touch emulation through 768px; the desktop check uses a desktop viewport. These are automated browser checks, not physical-device or Safari tests.

Coverage includes:

- Dashboard, customer/job lists and details, activity metadata, long text, attachments, estimates, change orders, and their forms.
- Document/field overflow, initial viewport scale, editable-control text size, unwrapped badges, clipped submit labels, action sizing, and scrolling tables.
- Keyboard navigation, Escape/focus restoration, breakpoint changes, Turbo Back/Forward, and mobile sign-out.
- Job creation/editing with date and datetime values, validation responses, and adding/removing/saving estimate and change-order line items.
- Sign-in, registration, password-reset forms, account settings, 2FA setup/recovery/management/challenge, and pagination for both lists.

## Regression-run findings

On October 29, 2026, `env -u DEBUG PARALLEL_WORKERS=1 bin/rails test` passed 383 tests and 4,558 assertions. The focused responsive suite passed all 12 tests; the existing 2FA suite passed all four tests after its navigation helper was updated to wait for the mobile button. The final `env -u DEBUG TEST_HEADLESS=true PARALLEL_WORKERS=1 bin/rails test:system -- --seed 3418 --verbose` run passed 39 tests and 3,385 assertions, without CI retries. RuboCop passed on the four changed Ruby files, and `git diff --check` passed.

One full system run (seed 11791) exposed an intermittent existing pagination-history test failure: Back restored `/jobs` while the search field and results still reflected “Paged” (52 results instead of 53). Its isolated check passed with 27 assertions. An unchanged HEAD comparison did not reproduce that history failure, but encountered a Selenium inspector error (“Node with given id does not belong to the document”) in the existing 2FA test. The history cause remains unresolved; a later passing run does not establish a fix. No production filtering behavior, skips, sleeps, or retries were added for these observations.

## Changed files

```text
app/assets/tailwind/application.css
app/helpers/application_helper.rb
app/javascript/controllers/navigation_controller.js
app/views/layouts/application.html.erb
app/views/jobs/_form.html.erb
app/views/estimates/_form.html.erb
app/views/account_security/setup.html.erb
app/views/account_security/show.html.erb
app/views/two_factor_challenges/new.html.erb
test/system/responsive_layout_test.rb
test/system/pagination_test.rb
test/system/two_factor_authentication_test.rb
docs/AUTHENTICATION_FORMS.md
docs/MOBILE_RESPONSIVENESS.md
```

## Remaining physical-browser checks

No physical mobile devices were available for this change. Verify Safari on iOS and Chrome on Android using disposable accounts; record browser/OS versions and any actual hardware tested.

1. Load sign-in and core screens in portrait and landscape. Focus/autofocus fields, dismiss the software keyboard, and confirm natural scale, usable controls, pinch-to-zoom, and larger-text accessibility.
2. Open/close Menu, follow every link, use Back/Forward, rotate while the menu is open, and sign out. Check VoiceOver/TalkBack and an external keyboard where available.
3. Create/edit a job with start, estimated-completion, and completed-at values. Open native date/datetime pickers and verify empty/populated values, localized text, and picker affordances fit their containers.
4. Review long names, status pills, activity history, attachments, line-item forms, validation messages, local table scrolling, and pagination.
5. Complete registration/password reset and 2FA setup, recovery sign-in, regeneration, and disabling with the software keyboard open. Use the existing Safari AutoFill checklist in [AUTHENTICATION_FORMS.md](AUTHENTICATION_FORMS.md) for saved credentials.
