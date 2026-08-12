# DrsListing

AI-powered healthcare assistant & doctor discovery app.

## Development Tooling

The Supabase scripts talk to the live project's Management API and read
the access token from `.env.deploy` (or the `SUPABASE_ACCESS_TOKEN` env
var). Create a token at supabase.com/dashboard/account/tokens.

- **`supabase/deploy_booking.py`** — deploy the booking-page Edge
  Function (migration + function + secret), then **auto-verify** the
  whole chain: GET form render + end-to-end POST booking (see
  `verify_booking_post.py`). Pass `--skip-post-verify` to deploy only.

- **`supabase/deploy_booking.py --fresh --project-ref <ref>`** —
  bootstrap a **brand-new environment**: applies the consolidated
  full-schema migration
  (`supabase/migrations/20260807000001_full_schema_all_fields.sql`,
  every table/column/policy/trigger) instead of the incremental
  booking-chain ones, then deploys the Edge Function + secret and
  verifies as usual. `--project-ref` is required with `--fresh` — the
  full schema must never run against the existing production DB.

- **`supabase/verify_booking_post.py`** — end-to-end POST check against
  the live booking-page Edge Function. Simulates exactly what the static
  booking page (`booking.html` — the drsListing-web GitHub repo) does: books a test
  appointment, confirms the row landed as `'Pending'` in the live
  `appointments` table, and — when the chosen slot carries a fee — that
  the booking-page function also recorded the matching `payments` row
  (Pending / offline / slot fee). Then deletes the test rows
  (marker-guarded).
  It also runs automatically as deploy step 5. Flags: `--keep` (leave
  the test row for `cleanup_test_data.py`), `--doctor <placeId>`,
  `--project-ref <ref>` (target a different project — forwarded
  automatically by `deploy_booking.py`).

- **`supabase/cleanup_test_data.py`** — remove any leftover test/QA rows
  from verification runs. `--dry-run` previews, `--yes` deletes.

- **`supabase/test_extract_const.sh`** — regression guard for the
  `extract_const()` parser in `preflight_qr_flow.sh`, which reads
  `bookingHost`/`bookingSharedSecret` from `lib/config/constants.dart`.
  Run after any edit that reformats those constants (it must keep
  passing through single-line, two-line, and commented-out formats).

- **`supabase/verify_browser_flow.sh`** — real-browser (Chrome
  headless) check of the static booking site: the root landing page
  renders (not a host 404), the query-preserving JS rewrites the
  button href with the token, and the `/book/` form renders visible
  for a valid QR link. Pass `--with-post` to also run the full POST
  booking chain (`preflight_qr_flow.sh`).

- **`supabase/deploy_notifications.py`** — deploy push notifications
  (FCM): the device-tokens migration + the `notifications` Edge
  Function + the `booking-page` re-deploy (it now fires the doctor
  push on web/QR bookings), sets `NOTIFY_SHARED_SECRET` +
  `FIREBASE_SERVICE_ACCOUNT`, then smoke-tests the live function.

- **`supabase/verify_fcm_delivery.py`** — end-to-end FCM delivery check
  against the live notifications function, no device needed. Creates
  isolated probe users + appointment + device token (marker-guarded),
  calls the deployed function exactly like the app does, and confirms a
  REAL push was attempted (HTTP 200 instead of 503 = the service
  account OAuth chain works) and a history row landed with the enriched
  payload. Then cleans up. Fails fast with setup instructions if
  `FIREBASE_SERVICE_ACCOUNT` is missing. Flags: `--keep`,
  `--project-ref <ref>`.

- **`supabase/verify_booking_notify.py`** — end-to-end check of the
  **in-app booking → doctor notification** chain: inserts an appointment
  with the exact payload `AppointmentController.bookAppointment()` sends
  (APT-prefixed id, `'Upcoming'`, `consultation_type`, `patient_phone`,
  `doctor_details`, …), fires the live notifications function exactly like
  `NotificationService.notifyAppointmentBooked()` does, and asserts the
  **doctor's** notification history row landed with the enriched payload
  (doctor_name, patient_name, date, time). The probe doctor carries a
  registered device token — the notifications function writes NO history
  row when the doctor has zero devices (the shared-phone bug fixed in
  `NotificationService.removeTokenForUser`). Then cleans up. Flags:
  `--keep`, `--project-ref <ref>`.

- **`supabase/deploy_payments.py`** — apply & verify the **payments**
  table (UPI / offline consultation fees). Applies
  `supabase/migrations/20260809000001_add_payments_table.sql`, then
  verifies through the public PostgREST API exactly like the app:
  INSERT with the `x-user-id` header succeeds, without it is rejected,
  and SELECT is scoped to the caller's own rows. Probe rows are cleaned
  up afterwards.

- **`supabase/deploy_payments_rls.py`** — apply & verify the
  **doctor-side payments RLS** (`20260809000002_add_payments_doctor_rls.sql`):
  a clinic (a `doctors` row whose `user_id` is the caller's `x-user-id`)
  can READ payment rows for its own appointments and flip their status —
  the **offline 'Pending' → 'Paid' / 'Refunded'** actions on the doctor
  appointments screen. UPDATE is column-restricted to `payment_status` /
  `paid_at` / `updated_at`. Verifies through the public API that the
  owning clinic's UPDATE succeeds (and sets `paid_at`), while the patient,
  a doctor of a different clinic, and header-less requests are all
  blocked; the owning clinic's SELECT is scoped, and header-less SELECT
  returns nothing. Probe rows are cleaned up afterwards.

```bash
# Deploy the booking-page Edge Function + migration + secret, then
# auto-verify the whole chain: GET form render + end-to-end POST booking
# (books a test appointment, confirms 'Pending' in the live DB, cleans up)
python supabase/deploy_booking.py

# Deploy only — skip the end-to-end POST check (e.g. no test rows wanted)
python supabase/deploy_booking.py --skip-post-verify

# Bootstrap a brand-new environment: consolidated full schema + Edge
# Function + secret + verification, all against the new project ref
python supabase/deploy_booking.py --fresh --project-ref <new-ref>

# Verify the live booking chain on its own (book -> confirm -> clean up)
python supabase/verify_booking_post.py

# Remove test/QA rows created during verification runs
python supabase/cleanup_test_data.py --dry-run   # preview
python supabase/cleanup_test_data.py --yes       # delete

# Deploy push notifications (FCM) — migration + Edge Functions + secrets
python supabase/deploy_notifications.py

# Prove real push delivery works (service account + FCM chain, no device)
python supabase/verify_fcm_delivery.py

# Prove an in-app booking produces the doctor's notification history row
python supabase/verify_booking_notify.py

# Apply & verify the payments table (UPI / offline consultation fees)
python supabase/deploy_payments.py

# Apply & verify the doctor-side payments RLS (Mark Paid / Refund actions)
python supabase/deploy_payments_rls.py
```

## Consultation Payments (UPI)

Tele & Video consultations are paid up-front when booking: the patient
picks **Online Pay (UPI)** — an `upi_india` intent to GPay/PhonePe/
Paytm for the slot's consultation fee — or **Offline Pay** (settle at the
clinic). In-clinic visits book directly with an offline "pay at clinic"
record. **Only a CONFIRMED payment (`success` status) proceeds to
booking** — an unconfirmed `submitted`, `failed` or cancelled payment
never books the slot. When a payment is declined (e.g. "failed as per
UPI risk policy" from the UPI app) or left unconfirmed, a clear dialog
reassures the patient that **no money was deducted** and offers
**Try Again** (re-picks another UPI app), **Pay Offline** (books with a
pay-at-clinic record), or **Cancel** — so a blocked payment never leaves
the patient stuck.

Every payment is stored in the **`payments`** table (see
`supabase/migrations/20260809000001_add_payments_table.sql`) linked to the
appointment (`appointment_id`), patient (`patient_id`) and doctor
(`doctor_place_id`), with status (`Pending`/`Paid`/`Failed`/`Refunded`),
method (`online`/`offline`), amount, UPI transaction id, receiver VPA and
payment timestamp. RLS scopes each patient to their own rows via the
`x-user-id` header (same convention as the notifications table).

**Doctor side** (`supabase/migrations/20260809000002_add_payments_doctor_rls.sql`):
on the Appointments screen each card shows the payment for that booking
(amount + status chip). An **offline Pending** payment — "pay at clinic" —
gets **Mark Paid** / **Refund** actions right on the card, so the clinic
settles it as soon as the cash is received; the flip writes
`payment_status` + `paid_at` and the card updates in place. Only clinics
that own the appointment (their `doctors` row's `user_id` matches the
caller) can do this, and the UPDATE column grant limits them to the status
fields — never the amount, patient or method.

**Web / QR bookings** (the `booking-page` Edge Function) record the same
payment automatically: when the booked slot carries a fee, the function
inserts a `payments` row — method `offline` (the web flow is pay-at-clinic;
there is no UPI intent on the page), status `Pending`, amount = the slot's
fee **resolved server-side from `doctor_slots`** (never trusted from the
client). It then shows up in the patient's Payment History and on the
doctor's appointments card exactly like an in-app offline payment, ready
for the clinic to mark Paid/Refunded. Recording the payment is non-fatal
and never fails a booking. The booking page surfaces it too: the **success
card** shows a fee chip (e.g. `💵 ₹800 · Offline (Clinic)`) right after
booking, and the **web history** accordion adds a **Fee** row per booking
from the payment summary the `history` endpoint now attaches — so the
patient always sees what they owe and what the clinic settled.

**Who the patient pays** — each clinic can set its **own receiving UPI
VPA** (the `upi_id` field on its `doctors` row, editable from the doctor
profile). When set, it overrides the app-wide default and is surfaced at
every step of the online-pay flow so the patient sees the recipient
before paying:

1. **Payment method sheet** — the "Consultation Payment" bottom sheet
   that opens for Tele/Video bookings shows a **`Pay to: clinic@okhdfcbank`**
   pill in its header, right under the consultation type + fee.
2. **UPI app picker** — before the patient taps an app, the picker shows
   a payee badge with the clinic name and VPA
   (**`Dr. Name (clinic@okhdfcbank)`**).
3. **UPI intent & record** — the `upi_india` intent is addressed
   to the doctor's VPA (with the doctor's name as the receiver), and the
   recorded `payments` row carries it as `upi_id`.

The `upi_india` package is **vendored** at `third_party/upi_india/` (a
path dependency in `pubspec.yaml`): upstream 3.0.1 carries a dead import
of `PluginRegistry.Registrar` (removed in Flutter 3.35+) that breaks the
Android build, and its module predates AGP 8's `namespace` requirement.
The vendored copy patches both; no other code changes.

Doctors that haven't set their own VPA fall back to the app-wide merchant
VPA in `AppConstants.upiReceiverVpa` / `upiReceiverName`
(`lib/config/constants.dart`) — replace the placeholder with the real
merchant VPA before going live.

> **Note:** intent-based UPI has no server-side verification, so only a
> `success` status is trusted as paid. A `submitted` (unconfirmed)
> payment does **not** book the appointment — it is treated as
> not-paid until the clinic confirms separately. For production-grade
> payment verification, swap `UpiPaymentService` for a gateway SDK
> (Razorpay/PhonePe) that returns a server-verifiable transaction id.

## One Patient, One Doctor at a Time

A patient can hold **at most one active appointment** (Pending/Upcoming)
at a time, and the next booking is only allowed once **12 hours** have
passed since their most recent booking was **created** — a Completed or
Cancelled appointment still starts the clock (the rule keys off the
booking moment, not the visit). Blocked bookings explain why: the booking
screen shows an amber notice ("You already have an appointment booked…"
or "…12 hours after your last booking…" with the remaining time), the
same message appears again as a snackbar if the patient taps **Book**, and
the web/QR page surfaces the identical wording from the server.

The rule is enforced in **three layers** (same pattern as the slot rule):

1. **Booking screen** — refreshes the patient's appointments on open and
   re-checks right before booking (`AppointmentController`
   `bookingBlockMessage`, `lib/controllers/appointment_controller.dart`),
   showing the banner + blocking the Book action.
2. **Web/QR booking** — the `booking-page` Edge Function runs the same
   gate server-side (`bookingGateError`,
   `supabase/functions/booking-page/index.ts`) so a scan can't bypass it.
3. **Database** — the `enforce_one_active_booking_rule` trigger
   (`supabase/migrations/20260812000001_enforce_one_active_booking_rule.sql`,
   applied by `deploy_booking.py`) is the final authority: it rejects any
   INSERT that would give a patient a second active booking or a second
   booking within the 12h window — so even two devices booking in
   parallel (e.g. while a UPI payment is in flight) can't slip through.
   Reschedules (UPDATEs) and Cancel/Complete status changes are never
   blocked. The app and Edge Function both translate the trigger's error
   markers back into the friendly gate message.

## Reschedule Appointments

Patients can move a **Pending** (awaiting clinic confirmation) or
**Upcoming** appointment to a different available slot right from the
appointment history screen: tapping the card opens the **details sheet**,
whose **Reschedule** action is the single entry point to the reschedule
screen
(`lib/screens/appointment/reschedule_appointment_screen.dart`). The card
list itself stays clean — no Reschedule chip alongside Call/Map/Cancel —
and the card's former phone cell was replaced by a full-width
**Consultation** row (e.g. "Video Consultation") so the patient sees at a
glance what they booked; the doctor's phone still lives in the details
sheet, one tap away via the **Call** action. A **Pending** appointment
asks for confirmation first ("Reschedule pending appointment?") because
the clinic hasn't confirmed it yet.

The screen reuses the booking flow's slot picker — the same 14-day date
strip + time chips grouped by consultation type, driven by the same
`AppointmentController` slot helpers (`getTimeSlotsForDay`,
`getSlotTypeLabel`, `isSlotBooked`, `isSlotInPast`, unavailable-date
ranges) — so picking a new slot works exactly like booking one. The
appointment's **own** slot stays selectable (`isSlotBookedExcluding`), so
the patient can keep the same time or move away from it.

Confirming calls `AppointmentController.rescheduleAppointment`, which
updates only the slot-defining columns (`appointment_date`,
`appointment_time`, `consultation_type`). **Double-booking is impossible:**
the `enforce_slot_booking_rule` DB trigger fires on that UPDATE and
rejects the move when the new slot is already occupied by another
non-Cancelled appointment — the screen then shows the same "slot was just
booked" message as the booking flow. Completed and Cancelled appointments
never show the Reschedule action in the details sheet.

The doctor is notified ("Appointment Rescheduled" push + in-app
Notification Center history row, new `appointment_rescheduled` event), and
doctors can opt out of reschedule alerts from **Profile → Notification
Settings** — the "Reschedules" toggle next to the existing
bookings/cancellations/status ones.

## Payment History (filter bar)

The patient's **Payment History** (Profile → Payment History) and the
doctor's **clinic payment history** (Dashboard → Payment History) share one
screen (`lib/screens/profile/payment_history_screen.dart`): a gradient
summary card (total Paid + Pending) above the payment records, each row
opening a details sheet with the transaction id, UPI id, appointment id
and timestamp.

A horizontal **filter bar** always shows **"All"** (the full list), a
**"Custom range"** chip (an arbitrary date-range picker), and the two
one-tap presets **"Last 30 days"** and **"This month"** — there is no
month-chip window anymore. All of the range options scope the list, the
summary card and the CSV export the same way: the title reads
`Payment Summary — 10 – 12 Aug 2026` (or `1 – 15 Aug 2026` for the
This-month preset), the record count follows it, and export filenames
become `payments_2026-08-10_2026-08-12.csv`. Picking any range replaces
the previous one; tapping the Custom-range chip again reopens the
picker on the previous selection.

The summary card carries a **yearly strip**: the combined (paid +
pending) total for the rolling 12-month window next to the current
month's — so the year picture is always one glance away, independent of
the selected filter. When a **custom range is selected, the strip
adapts**: the comparison figure becomes that selected period (its span
+ combined total, e.g. `10 – 12 Aug 2026` instead of the calendar
month), so the strip reads "window vs what you're viewing". The strip
is also a **filter shortcut**: tapping the **window figure** resets the
filter to "All", and tapping the **comparison figure** jumps straight
to the period it's showing (the selected range, or the "This month"
preset when nothing is selected). This works identically on the
**doctor's clinic payment history** — both sides share the same screen.

The summary card's **Paid / Pending pills** are **status-filter
shortcuts** too: tapping one narrows the list (and the CSV export) to
that status — e.g. tapping **Pending** shows only the outstanding fees,
with the pill highlighted (a ✓) and the footer reading
`1 Pending payment record`. The summary figures stay the full scope
split (the pill filters the list, it doesn't re-scope the card), the
status composes with the selected range, and re-tapping the
**active pill** (or choosing the **"All" chip** / the strip's window
figure) clears it.

- **Tapping a range** filters the list to that period's records and
  scopes the summary card to it; a range with no matching payments
  shows the same scoped view with `0 payment records` and `₹0` totals.
- **Tapping "All"** restores the full all-time list and summary.

Grouping keys off each payment's `paid_at` (falling back to `created_at`),
and the filter works identically on both the patient and doctor sides.

A **share/export button** in the header (visible once there's data)
writes the **currently filtered** records — the selected range, or all
when "All" — to a CSV file and opens the system share sheet (WhatsApp,
email, Drive, …). The CSV is RFC 4180-escaped with one row per payment:
`Date,<name>,Consultation,Method,Status,Amount (INR),Transaction ID,UPI
ID,Appointment ID` (amounts as plain numbers so spreadsheets treat them
as numeric). The name column is **role-labeled per side**: the patient's
export reads **`Doctor Name`** (who they paid) and the doctor/clinic
export reads **`Patient Name`** (who paid them), mirroring the card
list. Filenames are `payments_<start>_<end>.csv` for a range and
`payments_all.csv` for all records — with `_pending` / `_paid` appended
(and ` · Pending` / ` · Paid` on the share subject) when a status pill is
active, so a status-filtered export never masquerades as the full scope.
Empty selections and failures surface as a snackbar, never a crash.

When the clinic has **no payments at all**, the doctor's empty state is
doctor-flavored — **"No fees collected yet"** with a fee-oriented message
— and carries a **"View Appointments"** call to action that jumps back to
the dashboard's Appointments tab (where the clinic settles offline
payments), instead of the patient's "No payments yet" text.

The **last filter is remembered**: whichever custom range, quick preset
or **status pill** the patient or doctor leaves the screen with
(including "All") is saved locally and restored the next time they open
Payment History — so the list reopens exactly where they left off. (A
legacy saved month from before the chip bar was removed is ignored and
the screen falls back to "All".)

## Push Notifications (FCM)

Appointment events trigger Firebase Cloud Messaging pushes:

- **Patient books an appointment** (in-app **or** web/QR) → the
  **doctor** is notified ("New Appointment Request").
- **Doctor changes a status** (Confirm/Cancel/Complete) → the
  **patient** is notified ("Appointment Confirmed/Cancelled/...").
- **Patient cancels** → the doctor is notified.
- **Patient reschedules** (moves an appointment to a new slot) → the
  doctor is notified ("Appointment Rescheduled").

Users can opt out per event from **Profile → Notification Settings**
(bookings, cancellations, reschedules, status changes). Preferences are
stored server-side on the `users` row (`notification_prefs` JSONB) and
enforced by the `notifications` Edge Function, so web/QR bookings honor
them too.

Every push is also recorded server-side in the `notifications` table, and the
**in-app Notification Center** (bell icon on the home screen, or **Profile →
Notification Center**) shows the full history log with an unread badge — even
pushes that arrived while the app was closed. Each card shows the **doctor**
it's about and a **destination hint** ("Opens Doctor Dashboard" / "Opens
Appointment History"), and tapping a row deep-links to that screen.

A **master switch** on the settings screen ("All Notifications") mutes every
alert at once via the `notification_prefs.all` key — checked first by the
Edge Function, with the per-event choices preserved underneath.

History is **retained for 90 days** and then auto-cleaned: a pg_cron job
(`prune-notifications-daily`, 03:00) runs `prune_old_notifications(90)` on
the `notifications` table, and the Edge Function prunes opportunistically
as a safety net. See
`supabase/migrations/20260806000006_add_notifications_retention.sql`.

### How it works

1. **Device tokens** — each logged-in device registers its FCM token on
   the `users` row via `add_device_token()` (multi-device JSONB array).
   On logout the token is removed again so a shared device never leaks
   the previous user's notifications — **except for doctor accounts**,
   whose token is deliberately kept so a clinic keeps receiving booking
   pushes even when a patient logs into the same shared phone (the
   multi-device array supports one token on many rows). See
   `supabase/migrations/20260806000002_add_fcm_device_tokens_to_users.sql`
   and `NotificationService.removeTokenForUser`
   (`lib/services/notification_service.dart`).

   **Known tradeoffs** (deliberate, security-bounded): a doctor token left on
   an abandoned/borrowed device keeps receiving clinic pushes until FCM
   reports it unregistered (there is no in-app "remove this device" action);
   and if FCM rotates the device token while a *patient* is logged into the
   doctor's shared phone, the new token registers only on the patient's row
   (the app can only write tokens to its own row via the `x-user-id`-gated
   `add_device_token` RPC) — the doctor's row re-syncs the current token on
   their next login.
2. **Sending** — the `notifications` Edge Function
   (`supabase/functions/notifications/index.ts`) mints a Google OAuth2
   access token from the Firebase service account (self-signed RS256 JWT
   via Web Crypto — no external SDK) and sends through the **FCM HTTP v1
   API** (the legacy server-key API was shut down in June 2024). It
   verifies the caller is part of the appointment (patient or the
   doctor), then fans out to every registered device of the recipient.
3. **Triggers** — the Flutter app fires the function after a successful
   booking/status change; the booking-page function does the same for
   web/QR bookings.
4. **Preferences** — the recipient's `notification_prefs`
   (`{"appointment_booked", "appointment_cancelled", "appointment_rescheduled", "appointment_status_changed"}`,)
   are read inside the Edge Function and each recipient is skipped when the
   relevant event is toggled off (default: all on). See
   `supabase/migrations/20260806000003_add_notification_prefs_to_users.sql`
   and the `NotificationSettingsScreen`
   (`lib/screens/profile/notification_settings_screen.dart`).

### One-time setup (required once)

1. **Firebase project** — the Android app already ships
   `android/app/google-services.json` (Firebase project
   `drslisting-ai`). The `com.google.gms.google-services` Gradle plugin
   + `POST_NOTIFICATIONS` permission are wired up.
2. **Service account** — Firebase Console → Project settings →
   **Service accounts** → **Generate new private key**. Save the JSON in
   `.env.deploy` as `FIREBASE_SERVICE_ACCOUNT` (multi-line is fine).
3. **Deploy** — `python supabase/deploy_notifications.py` applies the
   migration, deploys both Edge Functions and sets the secrets, then
   smoke-tests the live function.

### iOS (if needed)

Download `GoogleService-Info.plist` from the Firebase console (add an
**iOS app** with bundle id `com.drslisting.ai` — note: Firebase requires
it to differ from the Android package) and drop it into `ios/Runner/`.
Push-capable provisioning is also required for real devices. Without the
plist the iOS build still succeeds; notifications simply no-op.

## Database Schema

See **[`docs/schema.md`](docs/schema.md)** — auto-generated ER diagram + full
reference (tables, columns, RLS policies, functions, triggers, storage) for the
complete DrsListing database. Regenerate after any schema change with:

```bash
python supabase/gen_schema_docs.py
```

## Android build prerequisite (Firebase config)

`android/app/google-services.json` is **gitignored** (it holds Firebase
client API keys) and is not in the repo. Fresh clones must drop the file
into `android/app/` before the Android build succeeds — download it from
Firebase Console → Project settings → Your apps, and keep a local copy
(e.g. in the same directory as `.env.deploy`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
