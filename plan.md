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
