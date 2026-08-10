import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'models/device_info.dart';

/// Best-effort hardware metadata for display/support purposes only. Every
/// build target here is Android (Sunmi/tablet hardware per the README), so
/// this only bothers reading `AndroidDeviceInfo` — on any other platform it
/// just returns an empty [DeviceInfo] rather than throwing.
Future<DeviceInfo> collectDeviceInfo() async {
  if (!Platform.isAndroid) return const DeviceInfo();
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return DeviceInfo(
      manufacturer: info.manufacturer,
      model: info.model,
      osVersion: info.version.release,
      // `info.id` is the OS build fingerprint (Build.ID), NOT the real
      // Android ID — device_info_plus deliberately doesn't expose
      // Settings.Secure.ANDROID_ID at all. Descriptive only either way,
      // per DeviceInfo's own doc comment — never the pairing lookup key
      // (that's the app-generated installId).
      osBuildId: info.id,
    );
  } catch (_) {
    return const DeviceInfo();
  }
}
