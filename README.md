# kds_pos

Flutter POS app. Currently has one feature: the **Employee Terminal**
(`lib/Feactures/POS/EmployeeTerminal/`) — an employee-facing screen that fetches
menu items from Convex, builds a cart, and charges the total via the SoftPay
AppSwitch SDK on a SUNMI D3 Mini terminal (or any Android device with a
Softpay app installed).

## SoftPay AppSwitch integration

Card payments (including NFC taps and Apple/Google Pay wallets) are handled by
Softpay's AppSwitch SDK, which app-switches from this app to a separate Softpay
app installed on the same device, and switches back with the result. See
https://developer.softpay.io/sdk/ for the full SDK docs.

**Native side** (`android/app/src/main/kotlin/.../softpay/`):
- `SoftPayClientProvider.kt` — builds the Softpay `Integrator`/`Client` from `BuildConfig` values.
- `SoftPayPlugin.kt` — a `FlutterPlugin` exposing a MethodChannel
  (`com.proxiestudio.kds_pos/softpay`: `readiness`, `charge`, `cancelCharge`) and an
  EventChannel (`.../softpay/status`) for live processing updates. Registered in `MainActivity.kt`.

**Flutter side** (`lib/Feactures/POS/EmployeeTerminal/softpay_service.dart` +
`softpay_models.dart`) — thin Dart wrapper around those channels.

### Required setup (`android/local.properties`, gitignored)

```
SOFTPAY_MAVEN_URL=https://nexus.softpay.io/repository/softpay-integrator/
SOFTPAY_MAVEN_USERNAME=<Nexus username, from Softpay Support>
SOFTPAY_MAVEN_PASSWORD=<Nexus password, from Softpay Support>
SOFTPAY_INTEGRATOR_ID=<Integrator id, from Softpay Support - different for sandbox/production>
SOFTPAY_INTEGRATOR_SECRET=<Integrator secret, from Softpay Support>
SOFTPAY_MERCHANT_NAME=<your own label, not provided by Softpay - any non-blank string>
SOFTPAY_TARGET=sandbox   # sandbox | production | any
```

These are read by `android/build.gradle.kts` (Maven repo credentials) and
`android/app/build.gradle.kts` (exposed as `BuildConfig` fields consumed by
`SoftPayClientProvider`). Getting real values is a one-time thing per
organisation — email **support@softpay.io** for Nexus + Integrator credentials,
and to get the Softpay Sandbox app installed on a test device (via Firebase App
Distribution) with Merchant Credentials to log into it.

Testing requires the **Softpay Sandbox app** installed and logged in on the same
physical device — real cards/wallets don't work in Sandbox, use the Visa CDET
test-card emulator (Play Store) or physical test cards instead.

### Gradle notes specific to this SDK

- `android/app/src/main/AndroidManifest.xml` declares a `manifest/queries` entry
  for `io.softpay.sandbox` — required on Android 11+ to target the Sandbox app.
  Drop it if `SOFTPAY_TARGET` is ever switched to `production` only.
- `android/app/build.gradle.kts` adds `-Xjvm-default=all` to Kotlin
  `compilerOptions.freeCompilerArgs` — required by the SDK docs for its
  default-implemented Kotlin interface members to compile/link correctly.
- `SoftPayPlugin.kt` opts into `@OptIn(io.softpay.client.meta.DelicateSoftpayApi::class)`
  for `Request.abort(...)` (used to cancel an in-flight charge).

## Convex integration

Menu items live in a Convex table (`menu_items`: `name` string, `price` number
— major currency units e.g. SEK, not minor units — `available` boolean).

- **Deployment**: `https://glad-bear-64.eu-west-1.convex.cloud` (dev deployment
  of the "learn" project). Set in `lib/main.dart` via `ConvexClient.initialize`.
- **Backend functions** (the actual query/mutation code — Convex only runs
  TypeScript/JavaScript, so this can't live in Dart or Kotlin) are in a
  **separate repo**: `../kds_pos_backend` (sibling to this project, not
  inside it). Currently just `convex/schema.ts` + `convex/menu_items.ts`
  (a `list` query). To add/change functions: edit there, then
  `cd kds_pos_backend && npx convex dev` (or `npx convex deploy` for a one-shot
  push) — requires `npx convex login` once, linked to the existing project
  (not "anonymous"/local mode, which spins up an unrelated throwaway local DB).
- **Flutter side**: `lib/Feactures/POS/EmployeeTerminal/menu_service.dart`
  (calls `"menu_items:list"`) and `menu_models.dart`.

### Known issue: `convex_flutter` 3.0.1 needs manual patches to build

This package uses a Rust FFI native layer (via `cargokit`, shared tooling from
the `flutter_rust_bridge` ecosystem). As of version 3.0.1 (the latest on
pub.dev), building it on this project's Gradle version (9.1.0) fails out of
the box for two unrelated reasons. **These patches are applied directly to
the local pub cache, not vendored into this repo or tracked by git** (a
deliberate choice to avoid a duplicated package folder) — which means **any
new machine, teammate, or CI runner needs to reapply them** before `flutter
build apk` will succeed. If this becomes painful, revisit vendoring a patched
copy via a `path:` dependency override instead.

To reapply, edit these two files inside
`~/.pub-cache/hosted/pub.dev/convex_flutter-3.0.1/` (or wherever the cache
lives on that machine):

1. **`cargokit/gradle/plugin.gradle`** — Gradle 9 removed `Project.exec()`;
   the script needs to use the injected `ExecOperations` service instead:
   - Add imports: `import javax.inject.Inject` and `import org.gradle.process.ExecOperations`
   - Inside `abstract class CargoKitBuildTask extends DefaultTask`, add:
     ```groovy
     @Inject
     abstract ExecOperations getExecOperations()
     ```
   - Replace both `project.exec { ... }` call sites in the `build()` method with `execOperations.exec { ... }`

2. **`android/build.gradle`** — bump `compileSdkVersion 33` to `36` (or
   whatever this project's Flutter SDK's default `compileSdk` is) — several
   of the plugin's own androidx dependencies (activity 1.8.1, core-ktx 1.13.1,
   lifecycle 2.7.0, etc.) require compileSdk >= 34.

### Known issue: `flutter_rust_bridge` version mismatch

`convex_flutter` 3.0.1 declares `flutter_rust_bridge: ^2.11.1` (a loose caret
range) in its own `pubspec.yaml`, but its generated Rust bindings are only
valid against exactly `2.11.1`. Without a pin, `flutter pub get` resolves the
newest matching release (`2.12.0` at time of writing), and the app throws
`Bad state: convex_flutter's codegen version (2.11.1) should be the same as
runtime version (...)` on startup. Fixed via this project's own
`pubspec.yaml`:

```yaml
dependency_overrides:
  flutter_rust_bridge: 2.11.1
```

This one **is** tracked in git (it's a normal pubspec pin, not a cache patch),
so it doesn't need to be reapplied elsewhere. If a future `convex_flutter`
release fixes its own version constraint, this override can likely be removed.
