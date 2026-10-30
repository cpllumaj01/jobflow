# JobFlow demo walkthrough

JobFlow keeps a contractor's customer, scope, approvals, pricing, and files together from first estimate to completion.

**Customer → Job → Estimate → Change Orders → Completion**

## Before you start

Open **[the live demo](https://jobflow.cpllumaj.dev)** and sign in with the intentionally public credentials:

- **Email:** `demo@jobflow.test`
- **Password:** `passwordpassword`

The tour below takes about **90 seconds after sign-in**, whether exploring independently or presenting on a call. On mobile, open **Menu** to reach Dashboard or Jobs. For a presentation, sign in first and allow extra time if opening downloaded files.

**Leave shared demo data unchanged.** Viewing records and downloading the PDF or scope document are safe exploration steps. Use a separate account with fictional data for edits, uploads, approvals, completion, deletion, or 2FA; the shared account is editable, not a read-only sandbox.

## The tour

1. **Dashboard · 0–10 seconds.** Review active jobs, **Awaiting decisions**, **Jobs by status**, and **Contract overview**. Status bars and the customer/job count cards open the corresponding lists. Explain: “This tells a contractor where work stands and what needs follow-up. Contract value counts approved work, not pending proposals; it is not revenue or payment tracking.”

2. **Job workspace · 10–25 seconds.** Open **Jobs**, enter `Kitchen Renovation` in **Search jobs**, and choose **View** on the exact **Kitchen Renovation** row for **Johnson Residence**. The larger demo also contains similarly named jobs. Review the customer link, **In progress** status, dates, and three financial cards. Explain: “The approved $25,325 estimate plus $635 in approved changes makes the current agreement $25,960.” Point out **Change status** and **Complete job** without activating them.

3. **Estimate and PDF · 25–45 seconds.** Scroll down to the **Estimate** card and choose **View estimate →**. Show the quantities, unit prices, $25,325 total, and approved editing lock. Choose **Download PDF**; open the downloaded file if time permits. Explain: “Itemized scope and a portable estimate give the contractor a clear document to discuss with the customer.” **Mark as sent** records a status; it does not email the estimate.

4. **Change orders · 45–65 seconds.** Use **← Kitchen Renovation**, then **View change orders →**. Compare the approved **Under-cabinet lighting** ($635) with the pending **Larger kitchen island** ($1,700), draft pantry shelving, and rejected backsplash. Open **Under-cabinet lighting** to see its line items. Explain: “Proposed extras stay visible, but only approved changes increase the agreed contract value.”

5. **Files and Activity · 65–90 seconds.** Use the **Kitchen Renovation** job link to return. In **Attachments**, download `kitchen-renovation-scope.txt`; then scroll to **Activity**. Explain: “Project documents stay with the job, and recorded events show who changed what and when, with pricing snapshots where available.” The seeded kitchen currently shows **No activity yet**: the demo loader creates records directly, while application actions record events. Do not change the shared job to populate its history.

Demo records can change, and IDs change when the owner refreshes the dataset. Navigate by labels rather than bookmarked record URLs; treat the amounts above as the reference kitchen example, not a promise that every dashboard count stays fixed.

## Engineering talking points

- **Conventional Rails:** Rails 8, PostgreSQL, ERB, and Tailwind keep the core workflow server-rendered. Turbo and small Stimulus controllers support filtering, line items, and upload feedback without a separate frontend application.
- **Data and authorization:** jobs belong to customers owned by a user; nested resources and attachment downloads follow that ownership chain. Decimal line-item math produces derived contract totals. Approved estimates and change orders are locked against editing until their status changes.
- **Verification and delivery:** Minitest and Capybara/Selenium cover business workflows and cross-user access. GitHub Actions runs tests, lint, and security checks; Railway hosts the Docker-based deployment with PostgreSQL, persistent file storage, and background email delivery. Optional 2FA uses encrypted authenticator secrets and single-use recovery codes.

For development, API examples, and implementation detail, return to the [README technical reference](../README.md#technical-reference). Hosting and runtime configuration are in the [deployment guide](DEPLOYMENT.md).
