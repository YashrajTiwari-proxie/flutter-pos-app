/// Descriptive-only hardware metadata sent alongside pairing calls —
/// never used as a security/lookup key (that's `installId`), just shown to
/// staff in the admin dashboard so they can tell physical devices apart.
class DeviceInfo {
  const DeviceInfo({this.manufacturer, this.model, this.osVersion, this.osBuildId});

  final String? manufacturer;
  final String? model;
  final String? osVersion;
  final String? osBuildId;

  Map<String, dynamic> toJson() => {
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (osVersion != null) 'osVersion': osVersion,
    if (osBuildId != null) 'osBuildId': osBuildId,
  };
}
