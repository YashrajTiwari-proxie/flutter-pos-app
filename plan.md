# Unify pos Flutter app onto the admin-panel-v2 Convex backend

## Context

`pos/` (the Flutter app with four device flavours — POS/EmployeeTerminal,
Kiosk, HandHeld, OrderStatusDisplay) currently talks to `kds_pos_backend`, a
throwaway sibling Convex project with a single `menu_items` table (name,
price, available — no categories, no images, no restaurants/orgs, no auth)
and a POS-only `orders` table (Softpay transaction snapshots, refunds,
failures — no relation to a menu, no restaurant scoping). The deployment URL
is hardcoded once in `lib/main.dart`, wiring is ad hoc string-keyed Convex
calls scattered per-feature (`menu_service.dart`, `order_service.dart` live
under `EmployeeTerminal/` and Kiosk imports them directly by relative path),
and there is no device identity of any kind — `device_registration.dart` is
an empty stub file.

Meanwhile `convex_main/admin-panel-v2/packages/backend` is the real,
multi-tenant Convex backend already reviewed: organizations → restaurants →
menuCategories/menuItems (with images via `_storage`, stock status,
addons/customizations), orders/orderItems, and Better Auth for staff (RBAC)
and restaurant customers. It has no device/POS concept at all — that domain
is explicitly listed as deferred in its own `CLAUDE.md`.

Decisions already made with the user:
- **Single backend**: retire `kds_pos_backend`; every flavour talks to
  admin-panel-v2's Convex deployment.
- **Device identity**: add a first-class `devices` table + device-token auth
  in admin-panel-v2, independent of staff/customer accounts (no staff
  credentials living on unattended kiosk/handheld hardware).

This plan covers three things: (1) the backend additions admin-panel-v2
needs to support POS/kiosk/handheld/display devices, (2) a centralized Dart
data-access layer in `pos/lib` so all four flavours share one Convex client
and one set of typed models/repositories instead of duplicating/reaching
into each other's feature folders, and (3) a README documenting the result.
No code is written in this pass — this is the plan to review before
implementation starts (likely executed one step at a time per the ordered
list at the bottom).

## Part 1 — Backend additions (`admin-panel-v2/packages/backend/convex`)

### 1a. `devices` table (add to `schema.ts`)

```
devices: defineTable({
  restaurantId: v.id("restaurants"),
  name: v.string(),                 // "Front counter POS", "Kiosk 1"
  deviceType: v.union(v.literal("pos"), v.literal("kiosk"), v.literal("handheld"), v.literal("display")),
  locationId: v.optional(v.id("locations")),
  tokenHash: v.string(),            // sha256 of the token; raw token never stored
  isActive: v.boolean(),
  registeredAt: v.number(),
  lastSeenAt: v.optional(v.number()),
}).index("restaurantId", ["restaurantId"]).index("tokenHash", ["tokenHash"])
```

Token itself (`dv_<random>`) is generated at registration time, returned
**once** in the mutation response, and never persisted in plaintext — only
its hash is stored, mirroring how a real API-key system works (and how
Better Auth session tokens are already handled by the underlying component).

### 1b. `lib/deviceAuthz.ts` — new file, sibling to `lib/authz.ts`/`lib/customerAuthz.ts`

Convex functions can't read custom headers the way an HTTP endpoint can, so
the token travels as an explicit first argument on every device-facing call
— same pattern `customerAuthz.ts` already uses for `customerMutation`/
`customerQuery`. Add:

- `deviceQuery(builder)` / `deviceMutation(builder)` — wrap `query`/
  `mutation`, require `deviceToken: v.string()` merged into args, hash it,
  look up `devices` by `tokenHash`, reject if missing/inactive, patch
  `lastSeenAt` (mutations only — queries stay side-effect-free), and expose
  `ctx.restaurantId` / `ctx.deviceId` / `ctx.deviceType` to the handler —
  exactly the `ctx` augmentation shape `staffRestaurantQuery` already
  establishes in `lib/authz.ts`.

### 1c. `devices.ts` — new file, staff- and device-facing functions

- `register` — `staffRestaurantMutation("devices:write")`: creates a row,
  generates the token, returns `{ deviceId, token }` (token shown once in
  the admin dashboard UI, same "copy now, can't see again" UX as an API-key
  page).
- `list` — `staffRestaurantQuery("devices:read")`: devices for a
  restaurant, for a future admin-dashboard Devices settings page.
- `revoke` — `staffRestaurantMutation("devices:write")`: sets `isActive:
  false` (soft-disable, same convention as `staffProfiles.isActive`).
- `rename` — trivial patch, same permission.
- `heartbeat` — `deviceMutation`: no-op body; `lastSeenAt` update happens in
  the wrapper itself, so this just proves the token is still valid (used by
  the Flutter app's connectivity/keepalive loop, and by a future admin
  "devices online now" view).
- `whoAmI` — `deviceQuery`: returns `{ restaurantId, deviceType, restaurantSlug, restaurantName }` so a freshly-paired device can self-configure without a second staff-driven lookup.

New permission keys `devices:read`/`devices:write` need adding to
`authzConfig.ts`'s role ladder (owner+ by default, matching how sensitive
config like `enabledModules` is gated) — **and per this repo's own
documented gotcha, `staff.syncRolePermissions` must be run once for
existing accounts after the permission is added.**

### 1d. Menu access for devices

`menu.listPublic` already exists, is deliberately unauthenticated, and
already returns `imageUrl`/categories/items in the guest-safe shape — reuse
it as-is for Kiosk (self-order browsing has identical trust requirements to
a public storefront). For POS/HandHeld, staff need to see *unavailable*
items too (grayed out, not hidden) — add `menu.listForDevice` (`deviceQuery`)
that calls the same internal `getMenuForRestaurant` helper `menu.ts` already
has (currently private to the file — export it) and returns the full
shape, unfiltered, the way `listForRestaurant` does for staff.

### 1e. Device/staff-placed order creation

`orders.placeOrder` is a `customerMutation` — it requires a real
authenticated customer account (`ctx.customerId`) and is designed for the
future online-ordering storefront. Walk-in POS/kiosk/handheld orders have no
customer login. Add `orders.createDeviceOrder` (`deviceMutation`):
same cart-validation/pricing/coupon/delivery-zone logic as `placeOrder`
(worth factoring the shared body into a helper both call, rather than
copy-pasting ~150 lines), but:
- no `ctx.customerId` requirement — `customerName` becomes a required arg
  (defaults to `"Walk-in"` client-side), `customerId`/`customerEmail`/
  `customerPhone` stay optional, matching the schema's existing optionality.
- takes `deviceId` from the token context automatically (no explicit arg) —
  worth adding an optional `placedByDeviceId: v.optional(v.id("devices"))`
  field to `orders` in `schema.ts` so staff can see *which physical device*
  rang up an order.
- `paymentMethod` covers `"cash"` / `"card"` (Softpay) same as today.

### 1f. Payment/transaction recording

`orders.setPaymentStatus` only sets a free-text string — POS needs the full
Softpay transaction lifecycle `kds_pos_backend` already modeled (charge
success/failure, refund with a transaction snapshot, partial refunds). Add
a new table (structured event log, not fields bolted onto `orders`, since a
POS order can be refunded more than once):

```
orderPaymentEvents: defineTable({
  orderId: v.id("orders"),
  type: v.union(v.literal("charge"), v.literal("refund"), v.literal("failure"), v.literal("cancellation")),
  amountCents: v.optional(v.number()),      // present for charge/refund
  transaction: v.optional(v.object({ ...same shape as kds_pos_backend's transactionSnapshot... })),
  failureCode: v.optional(v.string()),
  failureMessage: v.optional(v.string()),
  createdAt: v.number(),
}).index("orderId", ["orderId"])
```

`orders.ts` gains device-facing mutations `recordPaymentResult`,
`recordRefund`, `recordCancellation` (deviceMutation, restaurant-scoped via
the order's own `restaurantId`) — same call shape the Flutter
`OrderService` already sends today, just pointed at the real backend and
schema instead of `kds_pos_backend`'s.

## Part 2 — Centralized Dart data layer (`pos/lib`)

Today `lib/Database`, `lib/Services`, `lib/Models` exist as empty
directories while the real (ad hoc, POS-only) Convex code lives under
`lib/Feactures/POS/EmployeeTerminal/`, and Kiosk imports those files
directly by relative path (`../POS/EmployeeTerminal/menu_service.dart` etc.)
— tight, one-directional coupling that breaks down the moment HandHeld
needs the same data and shouldn't have to import through POS's folder.

Move the shared Convex layer into the already-scaffolded top-level
directories, used by all four flavours:

- **`lib/Database/convex_client.dart`** — one `ConvexClient.initialize(...)`
  call, deployment URL from `--dart-define=CONVEX_URL=...` (fallback to a
  dev default) instead of the hardcoded literal in `main.dart` today, so
  dev/staging/prod builds can point at different deployments without a code
  change.
- **`lib/Database/models/`** — schema-accurate models replacing
  `menu_models.dart`/`order_models.dart`'s POS-only shapes: `Restaurant`,
  `MenuCategory`, `MenuItem` (with `imageUrl`, `categoryId`, `tags`,
  `stockStatus`, `priceCents` — field names matching the backend's JSON
  exactly, not a renamed `price`/`priceMinor`, to remove the unit-naming
  drift already visible between `menu_models.dart` (`price` as major-unit
  double) and `kds_pos_backend`'s `priceMinor`), `Order`/`OrderItem`,
  `Device`.
- **`lib/Database/repositories/`** — one class per domain, each a typed
  wrapper over `ConvexClient.instance.query/mutation/subscribe` calling the
  real function names from Part 1: `MenuRepository` (`menu:listPublic`
  for kiosk, `menu:listForDevice` for pos/handheld), `OrderRepository`
  (`orders:createDeviceOrder`, `orders:recordPaymentResult`,
  `orders:recordRefund`, `orders:recordCancellation`, staff-facing
  `orders:list`/`orders:updateStatus` for the display/KDS-style views),
  `DeviceRepository` (`devices:whoAmI`, `devices:heartbeat`).
- **`lib/Database/device_identity_service.dart`** — replaces the empty
  `lib/Feactures/device_registration.dart`. Holds the paired device's
  token/restaurantId/deviceType, persisted via `shared_preferences` (already
  a dependency, currently unused for this). On first launch with no stored
  token, surfaces a pairing flow (staff enters a restaurant-issued pairing
  code, or scans a QR the admin dashboard's future Devices page renders,
  encoding the one-time token from `devices.register`) before the rest of
  the app can start. Every repository call goes through this service to get
  the current token — one place, not one per flavour.

`main.dart`/`app.dart` then only need to: initialize `ConvexClient` →
initialize `DeviceIdentityService` (show pairing UI if unpaired) → hand
control to the existing `appMode` switch. `EmployeeTerminalScreen`,
`KioskScreen`, and the still-to-be-built `HandHeldScreen` all consume
`MenuRepository`/`OrderRepository` instead of reaching into each other's
folders. `settings_screen.dart`'s currently-disabled "Your Restaurant" nav
entry becomes the real screen for viewing/re-pairing device identity.

`printer_service.dart`/`softpay_service.dart`/`order_display_service.dart`
are untouched — they're hardware/native-bridge integrations, not backend
data access, out of scope here.

## Part 3 — README

New `pos/README.md` section (replacing the current "Convex integration"
section, which still describes `kds_pos_backend`) covering:
- Architecture: one shared `admin-panel-v2` Convex backend, `lib/Database`
  as the single client/model/repository layer, four flavours consuming it.
- Device pairing flow and where the token is stored.
- How to point a build at a different Convex deployment
  (`--dart-define=CONVEX_URL=...`).
- Migration note: `kds_pos_backend` is retired; its `menu_items`/`orders`
  tables have no successor data (dev-only placeholder data) — nothing to
  migrate.

## Suggested implementation order (execute one step at a time)

1. Backend: `devices` table + `deviceAuthz.ts` + `devices.ts` + permission
   keys + `syncRolePermissions` reminder.
2. Backend: `menu.listForDevice`, `orders.createDeviceOrder`,
   `orderPaymentEvents` + the three device-facing payment mutations.
3. Flutter: `lib/Database` (client, models, repositories,
   `device_identity_service.dart`) + pairing UI.
4. Flutter: rewire `EmployeeTerminalScreen`/`KioskScreen` onto the new
   repositories; remove the old `EmployeeTerminal/menu_service.dart`/
   `order_service.dart`/`menu_models.dart`/`order_models.dart`.
5. README rewrite.

## Verification

- Backend: extend the existing e2e test pattern (`packages/backend/test/`,
  live against `convex dev`) with a `test/devices.ts` suite — register a
  device, call `whoAmI`/`heartbeat` with its token, confirm a revoked
  device's token is rejected, confirm `createDeviceOrder` produces the same
  `orders`/`orderItems` rows `placeOrder` does minus the customer
  requirement.
- Flutter: `flutter analyze` clean; manually pair a dev build against a
  local `convex dev` deployment for each of the `pos`/`kiosk` flavours
  (`display`/handheld have no real screens yet to smoke-test beyond
  compiling) and confirm menu images render and a test order round-trips.

---

## Deferred: Practice ("Övning") / Proforma ("Ej kvitto") receipts — NOT SCHEDULED

**Status: not planned for implementation.** Sales has no current plans for a
Test/Training mode — this section exists only so the gap is documented
somewhere concrete, not lost, in case Infrasec certification or a future
sales requirement calls for it. Do not start this without an explicit ask.

### Why this exists

Infrasec's TCS Certification Plan (`ReDocs/4. TCS Certification Plan.pdf`)
lists 10 required test cases for certifying a POS's TCS-D integration.
Test cases 9 and 10 are:

- **9. Practice receipt** — a training/demo sale that fiscalizes as
  "Övning" (practice), for staff training or store demos, without counting
  as a real sale in reports.
- **10. Proforma receipt** — an "Ej kvitto" (not-a-receipt) preview,
  typically for showing a customer the total before they commit to paying.

Both raw TCS-D operations already exist and work: `agentExercise.ts` and
`agentProfo.ts` in `admin-panel-v2/packages/backend/convex` are real,
device-callable (`deviceAction(["pos"])`) actions with the correct SKV
markers already wired in `lib/tcsXml.ts`. **Nothing calls them** except
`test/tcs-agent.ts`, a standalone dev script — there is no Flutter UI, and
`posPayments.ts`'s `reportEvent` action (the one real orchestration path
every actual sale/refund goes through) only handles
`charge | refund | failure | cancellation | unconfirmed`, with no
practice/proforma branch. So today, a real member of staff cannot trigger
either receipt type from the actual POS/kiosk apps.

### What it would take, if ever scheduled

Backend (`admin-panel-v2/packages/backend/convex`):
- Extend `posPayments.ts`'s `reportEvent` (or add a small sibling action)
  with `practice`/`proforma` outcome types — these never move real money
  and never touch `orders.paymentStatus`, so the orchestration is simpler
  than charge/refund: build VAT bands from a manually-entered amount (no
  real order needed), call `agentExercise`/`agentProfo`, write a `fiscal`
  row with `receiptType: "ovning"`/`"profo"` for the journal, return the
  shaped result for printing.
- No schema changes needed — `fiscal.receiptType`'s union already includes
  `"ovning"`/`"profo"`.

Flutter (`pos/lib`):
- A staff-only entry point, most naturally as a small "Test / Training
  mode" section in Settings (behind the existing settings lock — see
  `settings_lock_gate.dart`), not a button on the live charge screen, to
  keep it clearly separated from real sales.
- Enter an amount + VAT rate(s) manually (no cart/order involved), pick
  Practice or Proforma, submit, print. `printer_service.dart` already
  supports the required on-receipt markings pattern (`ReceiptKind.copy`
  prints "KOPIA" at 2× the amount text's size) — the same approach extends
  to a `.practice`/`.proforma` kind printing "Övning"/"Ej kvitto".

### Certification impact if left undone

Cert test cases 9 and 10 would need to be demonstrated to Infrasec via the
raw `test/tcs-agent.ts` script during the certification session itself,
not as real POS functionality — acceptable per the cert plan's own carve-out
("if an application would choose not to include the 'Pro forma' receipt
function... it is not included in the certification. Only certified
functions are allowed to be used in production."), as long as sales/legal
are fine certifying without these two receipt types.

## Deferred: Refund fiscal retry — NOT SCHEDULED

### Why this exists

A refund's money movement (SoftPay) and its TCS-D fiscalization
(`agentRefund`) are two separate steps — `posPayments.ts`'s `recordEvent`
durably marks the order `refunded` the instant the refund is reported,
*before* the TCS call happens, same pattern used for charges. But unlike a
charge, a refund whose fiscalization comes back `rejected`/`unconfirmed`
has no compensating action (there's nothing to "undo" — the money already
correctly went back to the customer) and, critically, no safe retry path:

- `posPayments.ts`'s dedup check (`existingFiscal.status !== "unconfirmed"`)
  treats a `rejected` fiscal row as already-fiscalized, so replaying the
  same `idempotencyKey` just returns the old rejected result instead of
  retrying the TCS call.
- Calling `reportRefundAndFiscalize` again without that key would create a
  second, distinct refund event on the same order — risking a real second
  SoftPay refund, actually moving money twice.

As a stopgap (2026-08-17), `orders_screen.dart`'s manual refund flow now
detects this case (`refundFiscal == null || !refundFiscal.success`) and:
tells staff plainly via a dialog that the refund needs manual follow-up,
never prints a receipt for it, and adds the order to a session-local
`_refundFiscalIssues` set that disables the Refund button for that order
for the rest of the app session (forgotten on next launch — no backend
field tracks this yet). `employee_terminal_screen.dart`'s auto-refund path
(triggered when the *original sale* can't be fiscalized) has the same
best-effort print-if-succeeded behavior but no equivalent UI warning, since
that path already ends in a distinct "call a manager" message.

### What it would take, if ever scheduled

- **Convex**: a new function (not touching any protected fiscal file —
  `posPayments.ts` is this app's own orchestration layer) that looks up a
  specific stuck `fiscal` row by ID, re-runs only the TCS call for it, and
  updates that same row in place — never creates a new `posPaymentEvents`
  row, so it can't double-refund money.
- **Flutter**: a real "Retry fiscalization" action (replacing the
  session-local warning-only stopgap above) that calls the new Convex
  function and prints the receipt once it succeeds; ideally the flagged
  state should persist server-side (e.g. a field/status on the `fiscal`
  row) so a stuck refund survives an app restart instead of just being
  remembered in-session.

### Certification impact if left undone

Low — this only matters if a refund's TCS-D call itself fails transiently
during real operation; it doesn't block demonstrating cert test case 7
(Normal refund) as long as that specific call succeeds, which is the
expected outcome in the Verify environment under normal network
conditions.

---

## Changelog

From this point on, every change made to this project (Flutter and Convex
alike) gets a dated entry here — not just plans for future work, so this
file stays a running record of what actually shipped, and why, that's easy
to scan without digging through git history.

### 2026-08-20 — Receipt redesign: 5 missing SKVFS Ch.7 §1 fields (Flutter-only)

**What changed.** `printer_service.dart`'s `printReceipt()` now prints all
five previously-missing required fields, matching the reference receipt
images the user supplied (`Img/WhatsApp Image 2026-08-19...jpeg`), and the
currency unit label changed from `SEK` to `kr`:

- **(b) Address where sales take place** — hardcoded `registerAddress`
  parameter, defaults to `"Testgatan 12, 123 45, Farsta"`. Printed near the
  top, before the KOPIA/REFUND marker.
- **(c) Date and time of the sale** — new required `saleDateTime` parameter.
  Sourced from data already available client-side, **not** a new Convex
  field: the moment a sale/refund actually succeeds
  (`employee_terminal_screen.dart`/`kiosk_menu_screen.dart`, captured via
  `DateTime.now()` right when the charge/refund completes, stored in a new
  `_lastSaleDateTime` field on the terminal screen so a delayed manual print
  still reflects the real sale time, not the print-button-tap time), or
  `order.placedAt` for a receipt **copy** in `orders_screen.dart` (a copy
  must show the *original* sale's date/time, not today's).
- **(e) Cash register designation** — hardcoded `registerDesignation`
  parameter, defaults to `"1"`. Printed as `"Register 1"` next to the
  address, distinct from the manufacturing number.
- **(k) Means of payment** — new `paymentMethod` parameter, defaults to
  `"Card"` (this business is card-only — see the payment-code-caution
  memory). Now an unconditional printed line (`Payment: Card (scheme ····
  panSuffix)` when a card scheme is known) replacing the old
  conditional-on-`cardScheme` block, so the field is never silently
  skipped.
- **(l) Manufacturing number of the control unit** — hardcoded
  `manufacturingNumber` parameter, defaults to `"NS12608061234011"` (from
  `Certs/1_Cert_setup_info.txt`). Printed as the very last line, after the
  control-code block, matching the reference receipt's placement.

**What's still hardcoded / temporary — real backend wiring not done yet.**
This pass was deliberately Flutter-only, per explicit instruction to defer
Convex changes. The three hardcoded defaults above (`registerAddress`,
`registerDesignation`, `manufacturingNumber`) and the `paymentMethod`
default are placeholders for testing/certification purposes, not real
per-restaurant/per-device configuration:

- `registerAddress`/`registerDesignation` have no backend source at all
  yet — no `restaurants`/`devices` field holds them. A real implementation
  would likely add these to `restaurants.fiscalIdentity` (address) and
  `devices` (register designation, distinct from `devices.manRegisterId`)
  and thread them through the same repository/device-identity path
  `printer_service.dart`'s callers already use for `headerText`/`footerText`.
- `manufacturingNumber` already has a real per-device home —
  `devices.manRegisterId` (added earlier this project) — but it is not yet
  wired through to the print call sites. That column today is pure
  data-recording with no runtime effect anywhere (`devicePrincipalCheck.ts`
  is untouched and still resolves fiscalization identity from
  `restaurants.fiscalIdentity` alone). Wiring the printed value to the
  device's actual `manRegisterId` is the natural next step once this data
  needs to be real rather than a fixed test value.
- `paymentMethod`'s hardcoded `"Card"` default is expected to stay correct
  indefinitely for this card-only business — flagged here only for
  completeness, not because it needs backend wiring.

**Files touched:** `lib/Feactures/POS/EmployeeTerminal/printer_service.dart`
(new parameters + print lines + `_formatDateTime` helper),
`lib/Feactures/POS/EmployeeTerminal/employee_terminal_screen.dart` (new
`_lastSaleDateTime` field, `_currency` → `'kr'`, wired into both the sale
print and the auto-refund print),
`lib/Feactures/Kiosk/kiosk_menu_screen.dart` (`_currency` → `'kr'`, wired
`saleDateTime: DateTime.now()`),
`lib/Feactures/POS/EmployeeTerminal/orders_screen.dart` (`_currency` →
`'kr'`, wired `saleDateTime: order.placedAt` for the copy print and
`DateTime.now()` for the refund print).

### 2026-08-20 — Fix: `_currency = 'kr'` was leaking into real SoftPay charge/refund calls

**Bug.** The receipt redesign above changed each screen's `_currency`
constant from `'SEK'` to `'kr'` for the *display/print* label — but that
same constant was also being passed as the `currency` argument to
`SoftPayService.charge()`/`.refund()`, which forwards it straight to the
native SoftPay AppSwitch SDK's `amountOf(amountMinor, currency)`. The SDK
needs a real ISO 4217 code; `"kr"` isn't one, so real charge/refund calls on
device started failing. Cashier-visible symptom: "Payment declined" with a
garbled `"!kr"` detail line (the raw, unmapped SDK failure message from the
invalid currency code, shown as-is by `friendlySoftPayMessage`). Reported by
the user from a live device test after installing the rebuilt release APK,
confirmed via screenshot.

**Fix.** Split display currency from payment-processor currency in all three
screens that call SoftPay: kept `_currency = 'kr'` for every print/on-screen
amount label (unchanged), and added a new `_paymentCurrency = 'SEK'`
constant used **only** for `SoftPayService.charge()`/`.refund()` calls:
- `employee_terminal_screen.dart`: `_charge()`'s `_softPay.charge(...)` and
  the auto-refund-on-fiscal-failure block's `_softPay.refund(...)`.
- `kiosk_menu_screen.dart`: same two call sites.
- `orders_screen.dart`: `_refund()`'s `SoftPayService.instance.refund(...)`.

No change to any print/display call site — those still correctly print
`'kr'`.

**Also fixed this pass (same session, from a live Bugsink report):**
- Added a friendlier fallback message for SoftPay's generic
  `"SoftPay charge failed"` failure text in `error_state.dart`'s
  `_knownSoftPayMessages` map (`"Payment could not be processed - please try
  again"`) — this specific SDK message wasn't mapped before, so it showed to
  the cashier verbatim. The underlying failure itself (a real, transient
  SoftPay-side decline, code `"error"`) is not a code bug; it's already
  correctly caught, reported to Sentry/Bugsink, and treated as a clean
  `recordPaymentFailure` (not "unconfirmed" — `"error"` isn't in the
  ambiguous-outcome list, so no double-charge-on-retry risk here).
- Added a real **company name** line to the printed receipt: a new
  `companyName` parameter on `printer_service.dart`'s `printReceipt()`,
  printed bold right below the logo/`"KDS POS"` fallback line, before the
  free-text `headerText`. Wired at all 4 real print call sites to
  `DeviceIdentityService.instance.identity?.restaurantName` — this is real,
  already-available data (resolved from `devices:whoAmI` at pairing time),
  not a new hardcoded placeholder like the address/register-designation/
  manufacturing-number fields above.

**Verification:** `flutter analyze` clean (12 pre-existing lint infos in
unrelated files, no new issues). Release APK rebuilt
(`app-pos-release.apk`, flavor `pos`) after `flutter clean` to rule out
stale-build-cache masking the fix — not yet verified against a live SoftPay
terminal charge; do a real charge + refund test on device before relying on
this for further testing/certification.

**Verification:** `flutter analyze` clean (12 pre-existing lint infos in
unrelated files, no new issues). Not yet verified against the physical
Sunmi printer — do a real print test before relying on this for a live
certification demo.

---

## Production-readiness audit (2026-08-20) — NOT YET FIXED

Full-codebase audit for what's missing/what can break in production, ordered
by severity. None of these are fixed yet — this is a punch list for future
work, not a changelog of completed changes.

### Blockers

1. **Release APK is signed with the debug keystore.**
   `android/app/build.gradle.kts:71-76` — `signingConfig =
   signingConfigs.getByName("debug")`. No real keystore or
   `keystore.properties` exists anywhere in the repo. Consequence: any
   release APK built today can be freely re-signed/tampered with by anyone,
   isn't eligible for the Play Store or Google Play App Signing, and any
   device-integrity check (Play Integrity/SafetyNet-style) would fail.
   **Fix:** generate a real upload keystore, wire it via a
   `local.properties`-style secret (same pattern already used for SoftPay),
   before any real device rollout beyond dev testing.

2. **Every restaurant prints the same fake fiscal identity — no override
   path exists.** `printer_service.dart`'s `printReceipt()` defaults
   `registerAddress` ("Testgatan 12, 123 45, Farsta"), `registerDesignation`
   ("1"), and `manufacturingNumber` ("NS12608061234011"). Confirmed via grep
   — **zero call sites override any of these three**; only `companyName`
   got wired to real data this session (see the 2026-08-20 receipt-redesign
   entry above). This means every device, at every restaurant, forever,
   prints the same hardcoded address and manufacturing number on real,
   legally-required SKVFS fiscal receipts. `fiscal_report_models.dart`
   already parses a real `companyName`/`registerDesignation` per fiscal
   report from the backend — that data exists and simply isn't threaded
   into the print calls. **Fix:** wire `registerDesignation`/`companyName`
   from that same backend source, and add a real per-restaurant
   `registerAddress` field plus wire `manufacturingNumber` to the existing
   `devices.manRegisterId` column (already scaffolded, currently a pure
   data-recording field with no runtime effect — see the deferred sections
   below). **This is a hard blocker the moment a second real restaurant
   goes live**, not a nice-to-have.

### High

3. **A transient fiscalization failure can permanently cost a customer
   their original receipt.** In `employee_terminal_screen.dart`, if
   `reportChargeAndFiscalize` doesn't resolve immediately (a network blip),
   `report` comes back null, so `_lastFiscal` stays null and the Print
   button is gated off for that session — even though the durable
   `OrderEventOutbox` will still fiscalize the sale later in the
   background. Nothing re-enables printing once it does. The only fallback
   (`orders_screen.dart`'s reprint) is Kopia-marked and capped at one copy
   per order (`hasReceiptCopy`). Exactly the transient-failure case the
   outbox exists to protect against ends up costing a true original
   receipt. **Fix:** surface a "fiscalization completed — print now"
   affordance once the outbox confirms success for an order still in view,
   or don't count that eventual print against the one-copy cap.

4. **Observability only covers SoftPay failures.** Exactly one
   `Sentry.captureException` call site in the whole app
   (`softpay_service.dart:145`). Fiscalization failures (e.g.
   `VAT_NOT_CONFIGURED`-style permanent errors), printer failures
   (`PrinterException` catches throughout), and outbox/Convex subscription
   errors all only `debugPrint` — invisible in production without a
   tethered debugger. A restaurant hitting a fiscal-config error today
   would leave zero trace in Bugsink. **Fix:** route all of these through
   `Sentry.captureException` too, not just SoftPay.

### Medium

5. **A real-looking secret is a silent hardcoded fallback in committed
   source.** `android/app/build.gradle.kts:44` bakes in a literal 32-hex-
   char `SOFTPAY_INTEGRATOR_SECRET` default. `local.properties` is
   correctly gitignored (the real secret is local-only), but a
   misconfigured/missing `local.properties` build silently compiles the
   fallback in rather than failing loudly. **Fix:** fail the build if the
   property is missing in a `release` build type, instead of silently
   defaulting.

6. **Silent sandbox fallback compounds with #5.** `SoftPayClientProvider.kt`
   — an unrecognized/missing `SOFTPAY_TARGET` silently falls through to
   sandbox mode (gradle default is `"sandbox"`). A release build shipped
   with bad/missing config would silently process sandbox-only transactions
   with no real money movement, hard to detect until a real payment
   mysteriously doesn't settle.

### Confirmed fine (checked, no issue found)

- Partial refunds and over-refund are already guarded client-side
  (`orders_screen.dart`: `if (cents > order.refundableCents) return;`) plus
  a server-side `ORDER_NOT_REFUNDABLE` rejection.
- `OrderEventOutbox` persists to `SharedPreferences` before any network
  attempt — genuine kill-safety for the money-movement report itself.
- `_isChargeInFlight`/`_lastFiscal` are in-memory only and reset on a real
  process kill mid-charge, but this only affects same-session double-tap
  protection and print-button gating (see #3) — the durable outbox and live
  Orders subscription already cover the actual money/fiscal-state truth, so
  this isn't a data-loss gap on its own.
- `convex_flutter`/`flutter_rust_bridge` known build issues are already
  documented in `README.md` with concrete patch steps.
- The "Deferred" sections below (Practice/Proforma receipts, Refund fiscal
  retry) remain accurately described as deferred — no change needed there.

### 2026-08-20 — Blocker #2 resolved: real per-restaurant/per-device fiscal fields, end to end

Closes out blocker #2 above (every restaurant printing the same hardcoded
`registerAddress`/`registerDesignation`/`manufacturingNumber`) and adds
automated daily Z-reports and per-restaurant currency, across both repos.

**Backend (`admin-panel-v2/packages/backend/convex`):**
- Schema: re-added `devices.manRegisterId` (lost in a prior uncommitted
  clone), added `devices.registerDesignation`, `restaurants.countryCode`,
  and `zReports.stockholmDate` + a `restaurantId_stockholmDate` index. All
  additive — no migration, no backfill, nothing destructive.
- New `lib/currency.ts` — `resolveCurrency(countryCode)`, `SE → {SEK, kr}`
  today, the one place a second country gets added later.
- `devices.ts`: re-added `setManRegisterId`, added `setRegisterDesignation`
  (same ownership-check/regex-validation pattern as the original). Extended
  `whoAmI`'s response with `manRegisterId`, `registerDesignation`,
  `registerAddress`, `orgNr` (all four newly exposed — `orgNr` and
  `registerAddress` already existed on `restaurants.fiscalIdentity`, they
  just weren't being sent to the device), and a resolved `currency` object.
- `restaurants.ts`: `getCountryCode`/`setCountryCode` (staff-facing,
  dashboard-editable — lower stakes than `fiscalIdentity`, which stays
  CLI-only/Infrasec-coordinated on purpose).
- `fiscalReports.ts`: refactored into one idempotent
  `generateZReportForRestaurant`, keyed on restaurant+Stockholm-date, used
  by both the manual device button and a new `generateDailyZReports` cron
  target — can never produce two Z-reports for the same restaurant on the
  same day. Confirmed Z-report generation has zero TCS-D side effects
  (pure local aggregation over already-fiscalized rows), so this
  automation carries no real fiscal-register risk.
- `crons.ts`: new daily job at 02:00 UTC (safely past Stockholm midnight
  year-round, with a buffer for late `OrderEventOutbox` retries to settle)
  generating yesterday's Z-report for every active, fiscally-configured
  restaurant. One restaurant's failure never blocks another's.
- Admin dashboard: re-created `DeviceManRegisterIdDialog.svelte`, added
  `DeviceRegisterDesignationDialog.svelte`, both wired into the devices
  table (new columns, pos-only). Added a country/currency `Select` to the
  existing Receipt settings page.
- Verified with `svelte-check` — zero new errors (22 pre-existing, all
  unrelated: missing private `@proxie-studio/*` packages and `.env` vars in
  this sandboxed clone, not caused by this work).
- **Not yet deployed** — none of this has gone through `npx convex
  dev`/`deploy` yet. The cron and new mutations won't run for real
  restaurants until that happens.

**Flutter (`pos/lib`):**
- `Database/repositories/device_repository.dart`: `DeviceWhoAmI` now parses
  `orgNr`, `registerAddress`, `manRegisterId`, `registerDesignation`, and a
  new `DeviceCurrency` (`isoCurrency`/`displaySymbol`).
- `Database/device_identity_service.dart`: caches these live (same pattern
  as `receiptConfig` — refreshed by the same long-lived `whoAmI`
  subscription every pairing and every push after, not re-queried per
  print) and exposes them via new getters (`orgNr`, `registerAddress`,
  `manRegisterId`, `registerDesignation`, `currency`).
- `printer_service.dart`: `registerAddress`/`registerDesignation`/
  `manufacturingNumber` are now nullable params with the fallback
  placeholder resolved *inside* `printReceipt` (one place, not duplicated
  per call site) — real values flow in from `DeviceIdentityService`, the
  hardcoded literals only apply if a restaurant/device genuinely hasn't
  been configured yet.
- All 4 real print call sites (`employee_terminal_screen.dart` ×2,
  `kiosk_menu_screen.dart` ×1, `orders_screen.dart` ×2) now pass
  `registerAddress`/`registerDesignation`/`manufacturingNumber` from
  `DeviceIdentityService.instance`.
- `_currency`/`_paymentCurrency` converted from hardcoded `'kr'`/`'SEK'`
  compile-time constants to getters reading
  `DeviceIdentityService.instance.currency` (falling back to `'kr'`/`'SEK'`
  only if unset) — the last piece of hardcoded fiscal display data in the
  print/UI path. `orders_screen.dart`'s one `const InputDecoration`
  referencing `_currency` had its `const` removed since the value is no
  longer compile-time.
- `orgNumber` was **not** changed — it was already correct, flowing
  through the live TCS-D fiscal call response (`fiscal.orgNr`), never
  hardcoded. Confirmed via investigation, not assumed.
- Verified: `flutter analyze` clean (12 pre-existing lint infos, no new
  issues).

**On-device caching, for the record:** confirmed no separate local
persistence (e.g. `shared_preferences`) is needed for these fields.
`DeviceIdentityService` already holds the latest `whoAmI` response in
memory and every print reads it synchronously — there's no
query-per-print. The live Convex subscription (not a one-shot fetch) is a
feature here, not overhead: a correction made on the dashboard (e.g. a
fixed register address) reaches every paired device immediately, and since
printing a receipt already requires a live TCS-D fiscal call to succeed
first, there's no realistic "offline print" scenario where a disk-persisted
copy would help that the live subscription doesn't already cover.

**Still outstanding:** deploy the backend changes; then configure a real
`restaurants.fiscalIdentity` (orgNr/registerAddress) and `countryCode` per
restaurant, and a real `devices.manRegisterId`/`registerDesignation` per
POS device, via the admin dashboard — until that's done, restaurants will
still see the same placeholder fallback text on printed receipts (by
design, not a bug).

### 2026-08-20 — Full compliance + operational sweep, and two fixes

Full audit of `ReDocs/` (Manufacturer's Declaration, SKV Test Protocol, TCS
Certification Plan) cross-checked against current code, plus a Convex
operational-risk pass and a Flutter-app-downtime pass. Findings and what
got fixed:

**Fiscal compliance — no new code gaps.** All 10 TCS certification test
cases have real code; 8 of 10 are reachable from actual staff-operable UI
(only Practice/Proforma, test cases 9-10, are dev-script-only — already
accurately tracked above as deferred, confirmed still accurate). Two real
gaps found in the Z-report **data** itself, not yet fixed:
- `zReports` has no cumulative "grand total" fields (all-time
  sales/returns/net) that the SKV Test Protocol requires alongside the
  period's own total.
- Goods and services sold aren't tracked separately — only one combined
  `goodsSoldCount`.

**The real remaining blocker is paperwork, not code**, per the same audit:
the Manufacturer's Declaration `.docx` is still Infrasec's generic
template (placeholder company name, blank legal/address fields, template
boilerplate compliance text never individually verified, no real test
evidence) and hasn't been submitted to Skatteverket. Not something fixable
by writing code. (Per the user, this is being handled separately — no
action needed here.)

**Convex operational risks found, not fixed this pass** (left for the
backend team, who have their own logging/Sentry setup):
- `generateDailyZReports` loops every restaurant inside one atomic
  mutation — a failure partway through (once restaurant count or history
  grows enough to hit Convex's transaction limits) rolls back *every*
  report generated earlier in that same run, not just the failing
  restaurant's. Fix would be fanning out via `ctx.scheduler.runAfter` (one
  scheduled mutation per restaurant) instead of one shared transaction.
- Zero alerting anywhere in the Convex backend — a full cron failure is
  currently silent until a restaurant notices a missing report.
- No consolidated list of required production env vars (`BETTER_AUTH_SECRET`,
  TCS client cert vars, Stripe/Resend keys) for a real go-live.
- **`BETTER_AUTH_SECRET` silently falls back to a hardcoded public string
  if unset in production** — a real, severe risk (forgeable staff sessions)
  specifically at go-live. A written explanation was handed to the user to
  forward to their backend developer directly; not fixed in this codebase
  since the user said this is backend-dev-owned.

**Fixed this pass — Z-report date-boundary strictness (Convex):**
`lib/fiscalReportAggregation.ts`'s `fiscal`-table query was unbounded — it
read the restaurant's *entire* fiscal history every time and filtered to
the period in memory, instead of bounding the query like the
`posPaymentEvents` query right next to it correctly does. Fixed by adding
a new `restaurantId_createdAt` index on `fiscal` (additive, no migration)
and querying directly against it with `.gte`/`.lte` on `createdAt`, same
pattern as `posPaymentEvents`. Now strictly bounded to the report's own
`[periodStart, periodEnd]` window: a sale fiscalized right after Stockholm
midnight has `createdAt` in the *next* period and is correctly excluded
from the day that just closed, landing in the following day's report
instead — never double-counted, never pulled backward.

**Fixed this pass — Flutter-side Convex-call timeouts (pos):** audited
every repository for scenarios where a genuine Convex network black-hole
(not an error — no response at all) could hang the Flutter app itself
with no recovery short of a force-restart. Found and fixed:
- `order_repository.dart`: `createOrder` had no timeout — a hang here
  permanently stuck `_isChargeInFlight`/`_isBusy` (cart edits blocked,
  Charge disabled, no Cancel button either, since that's gated on a
  payment stage this path never reaches). Added the same bounded
  `.timeout(_timeout)` (20s) pattern `device_repository.dart` already used.
- `order_event_outbox.dart`: `_send` (the single choke point for
  charge/refund/cancellation reporting via `posPayments:reportEvent`) had
  no timeout either. Added a 25s timeout — deliberately longer than the
  other repos', since this path makes a real TCS-D HTTP call server-side
  capped at 15s (`TCS_TIMEOUT_MS`), so the client-side bound needed to stay
  comfortably above that rather than racing a legitimately-slow-but-
  successful TCS round trip. Fits into the existing `catch (_)` handling
  with no other changes needed — a timeout is already treated the same as
  any other transient failure (entry stays durably queued, retried later).
- `menu_repository.dart`: `fetchMenu`/`fetchPublicMenu` (both currently
  unused dead code, but public API) had no timeout — added.
- `fiscal_reports_repository.dart`: `generateZReport` had no timeout —
  added; the existing `finally` block in `fiscal_reports_pane.dart` already
  resets `_isGenerating` on any exception, so no caller-side change needed.
- `journal_repository.dart`: audited, no fix needed — it has no one-shot
  query/mutation at all, only a live subscription.

**Not fixed this pass, still open:** the "infinite spinner with no manual
retry" gap on Employee Terminal's menu panel, Kiosk's menu view, and
Orders screen — all three only show a retry affordance once `onError`
actually fires, with no time-boxed fallback if a subscription's first
value never arrives at all. Lower urgency since the underlying
`convex_flutter` client does appear to auto-reconnect in the background,
so this is a bounded wait, not a guaranteed-permanent freeze — but there's
no user-visible "still connecting" affordance during that window.

**Verification:** backend changes checked with `svelte-check` (same 22
pre-existing, unrelated errors — missing private packages/env vars in this
sandboxed clone — zero new). Flutter changes checked with `flutter
analyze` (same 12 pre-existing lint infos, zero new issues).

### 2026-08-20 — Closed the "infinite spinner" gap on every live subscription screen

Follow-up to the timeout fixes above. Added `SubscriptionLoadingState`
(`error_state.dart`) — a small stateful widget that shows a normal spinner
while waiting on a live Convex subscription's first value, then after 12s
with neither `onUpdate` nor `onError` (a silent reconnect-in-progress, not
a clean failure) swaps to the same manual retry affordance `ErrorState`
already uses, instead of spinning forever with no way out. Tapping retry
resets the timer and shows the spinner again rather than instantly
re-showing "still connecting".

Wired into every screen that had a bare `CircularProgressIndicator()` on a
live subscription's initial-load state — six screens, three more than
originally scoped once a full sweep for the same pattern was done:
- `employee_terminal_screen.dart`'s menu panel
- `kiosk_menu_screen.dart`'s menu view
- `orders_screen.dart`
- `order_status_display_screen.dart` (found during the sweep — same exact
  bug, on the unattended customer-facing pickup board)
- `fiscal_reports_pane.dart` — only the X-report side (X is always a live
  computed value, so `null` there means "still loading"; the Z-report
  side's `null` correctly stays a permanent "no Z-report generated yet"
  empty state for a brand-new restaurant, not touched)
- `journal_pane.dart` — found during the sweep with a slightly worse
  variant of the same bug: the error banner and the spinner were
  independent, so an `onError` firing on the *initial* load left the
  spinner running underneath the error text forever, instead of ever
  reaching a retry button. Restructured so the initial-load error case
  shows `ErrorState` (spinner replaced), while the banner-plus-stale-data
  pattern (an error after entries already loaded once) is preserved
  unchanged.

**Verification:** `flutter analyze` clean (same 12 pre-existing lint
infos, zero new issues).

### 2026-08-20 — Recovered 5 fiscal-compliance fixes lost to the fresh admin-panel-v2 clone

The `admin-panel-v2` checkout used throughout this session is a genuinely
fresh clone (confirmed earlier — `git status` clean, `manRegisterId` on
`devices` already found missing and re-added). Prompted by the user asking
"did we add the no-copy-again enforcement as well?", checked systematically
for what else from earlier fiscal-compliance work never made it into this
clone (it only ever existed uncommitted in a now-gone previous checkout).
Found and re-applied **five** regressions, not just the one asked about:

1. **One-copy-only enforcement (SKVFS Ch.6 §3) — completely absent.**
   `posPaymentEvents.hasReceiptCopy` didn't exist in the schema at all, and
   `posReceipts.ts`'s `requestCopy` had no check before calling TCS-D. The
   Flutter app still expects and gates its Print button on this field
   (`orders_screen.dart`), so this was a real, active gap — the button
   would never have disabled and a cashier could print unlimited "Kopia"
   copies. Re-added: the schema field, `getLatestSaleFiscalForOrder`
   returning `hasReceiptCopy`, a new `markReceiptCopyIssued` internal
   mutation, and `requestCopy`'s pre-check (throws
   `RECEIPT_COPY_ALREADY_ISSUED` before any TCS call) + post-success mark.

2. **Ch.4 §9 auto-refund-on-unconfirmed — reverted to the old, narrower
   logic.** `posPayments.ts`'s `requiresRefund` had regressed to `status
   === "rejected"` only, with a comment explicitly arguing the old (wrong)
   reasoning ("never on unconfirmed, which might have actually
   succeeded"). Re-fixed to `status === "rejected" || status ===
   "unconfirmed"` — an unconfirmed fiscalization is just as much a
   compliance risk as a clean rejection if left as a charged-but-
   unfiscalized sale, so both now trigger an automatic refund.

3. **Abandoned-order cancellation cron — device orders excluded again.**
   `orders.ts`'s `cancelAbandonedPendingOrders` had regressed to skipping
   any order with `placedByDeviceId` set, so a POS/kiosk order stuck at
   `paymentStatus: "pending"` (app killed mid-charge, terminal
   disconnected) would never get swept. Removed the exclusion — the
   `order.status !== "pending"` guard already correctly protects an order
   staff advanced/cancelled themselves, so nothing else needed to change.

4. **Uncompleted-sales double-counting fix — missing entirely.**
   `fiscalReportAggregation.ts` had no `uncompletedEventOrderIds` exclusion
   set, so an order swept to `paymentStatus: "expired"` by the cron after
   already getting an `"unconfirmed"` `posPaymentEvents` row would be
   counted twice on the X/Z report. Re-added the exclusion set plus the
   `restaurantId_placedAt`-indexed expired-orders sweep, deduped against
   orders already counted via a real payment event.

5. `devices.manRegisterId` — already caught and fixed earlier this session
   (see the country-code/register-designation entry above).

**Why this matters going forward:** this clone has now silently regressed
fiscal-compliance code at least twice (this find, plus the earlier
`manRegisterId` one) purely because the prior work only ever existed
uncommitted in a different checkout. None of the five items above are
committed to git yet in *this* checkout either — until they are, a future
fresh clone/reset would lose them again. Recommend committing this
session's `admin-panel-v2` changes (and everything else already sitting
uncommitted here) before doing anything else with this repo.

**Verification:** `svelte-check` on the dashboard package — same 22
pre-existing, unrelated errors, zero new, across all five fixes.

### 2026-08-20 — Proactive "restaurant closed for ordering" indicator (POS + Kiosk)

The backend already enforces this (`requireOpenForOrders`/
`computeOrderingStatus` in `admin-panel-v2`'s `orders.ts`, shared with the
online storefront's `placeOrder` — not added this session, confirmed
pre-existing), but purely reactively: staff/customers only found out the
restaurant was closed after building a cart and tapping Charge, when
`createOrder` rejected it. No backend change needed — the enforcement
already covers `createDeviceOrder` (the function both POS and Kiosk call).

Added the proactive Flutter-side indicator:
- `order_repository.dart`: new `OrderingStatus` model +
  `subscribeToOrderingStatus()`, a live subscription to the backend's
  existing `restaurants:getOrderingStatusBySlug` — a public,
  unauthenticated query already used by the online storefront, reused
  as-is (no device-scoped duplicate added).
- New `lib/Widgets/ordering_closed_banner.dart` — `OrderingClosedBanner`,
  same "renders nothing while open" pattern as `ConnectivityBanner`.
- Wired into `employee_terminal_screen.dart` and `kiosk_menu_screen.dart`:
  subscribed alongside the menu subscription, shown as a banner next to
  `ConnectivityBanner`, and the Charge/Pay button disabled + relabeled
  "Closed for ordering" while closed. Guarded defense-in-depth in `_charge()`
  itself too, not just the button's `onPressed`.
- Deliberately best-effort: a failure to subscribe (or an `onError`) is
  silently ignored rather than blocking the screen — the server-side guard
  is the real enforcement; this is a UX improvement on top of it, not a
  replacement.

**Verification:** `flutter analyze` clean (same 12 pre-existing lint
infos, zero new issues).

### 2026-08-20 — Graphify knowledge graph refreshed

Rebuilt the graph to reflect everything above (the timeout fixes,
`SubscriptionLoadingState`, the README rewrite, this changelog's growth,
the recovered backend fixes). **860 nodes, 1002 edges, 43 communities.**
Images/icons were intentionally skipped this pass (unchanged since the
last full extraction, purely decorative) to save cost — everything else
was freshly re-extracted.
