/// Which of the three build targets this binary is - set per Android product flavor via
/// `--dart-define=APP_MODE=...` (see android/app/build.gradle.kts). Defaults to the cashier
/// POS app so an unflavored `flutter run` behaves exactly as before.
///
/// Shared between `app.dart` (which screen to show) and `main.dart` (device-level setup, e.g.
/// orientation lock, that differs per target) so both read the exact same value.
const appMode = String.fromEnvironment('APP_MODE', defaultValue: 'pos');
