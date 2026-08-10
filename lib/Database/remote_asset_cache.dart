import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-backed cache for restaurant-configured remote assets (receipt/kiosk header logos, the
/// kiosk background video) - keyed by URL, so a manager re-uploading (which always produces a
/// brand-new Convex storage URL, never reuses the old one) naturally invalidates the old cached
/// copy with no manual invalidation logic needed. Persists across app restarts, unlike Flutter's
/// own in-memory `ImageCache` or a plain instance-field cache - the whole point is these assets
/// (especially the video) shouldn't be re-downloaded from the server every cold start when they
/// almost never change.
class RemoteAssetCache {
  RemoteAssetCache._();

  static final RemoteAssetCache instance = RemoteAssetCache._();

  Directory? _dir;

  // De-dupes concurrent requests for the same URL (e.g. the header logo being read by both the
  // brand header and the fallback-background's centered logo at once) so they share a single
  // download/write instead of racing two independent ones against the same destination path.
  final Map<String, Future<File>> _inFlight = {};

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    // `getTemporaryDirectory` (not `getApplicationCacheDirectory`) - the most universally
    // supported path_provider API across platform versions, to minimize the chance of this
    // failing on a specific device/OS combination.
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/remote_asset_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  String _keyFor(String url) => sha256.convert(utf8.encode(url)).toString();

  /// Returns the local cached copy of [url], downloading it once on first use (per distinct
  /// URL, including across app restarts) and reusing that copy on every call after.
  Future<File> file(String url) {
    return _inFlight[url] ??= _fileUncached(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<File> _fileUncached(String url) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${_keyFor(url)}');
    if (await file.exists()) return file;
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      // Written to a temp path first and renamed into place only once the write fully
      // succeeds - `File.rename` is atomic within the same directory/filesystem, so a process
      // kill mid-download (very plausible on a kiosk left running for days) can never leave a
      // corrupt file sitting at the real cache path pretending to be a complete, valid entry.
      final tempFile = File(
        '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      return await tempFile.rename(file.path);
    } finally {
      client.close();
    }
  }
}
