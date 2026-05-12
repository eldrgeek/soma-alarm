// OTA update service for Pulse.
// Fetches manifest from the Tailscale OTA server, downloads APK, verifies
// SHA-256, and fires Android's install intent via open_filex.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const String _otaBase = 'http://100.72.65.118:8089';
const String _manifestUrl = '$_otaBase/latest.json';

class OtaManifest {
  final String version;
  final String versionName;
  final int buildNumber;
  final String commit;
  final String builtAt;
  final int size;
  final String sha256;
  final String url; // relative or absolute
  final String releaseNotes;

  OtaManifest({
    required this.version,
    required this.versionName,
    required this.buildNumber,
    required this.commit,
    required this.builtAt,
    required this.size,
    required this.sha256,
    required this.url,
    required this.releaseNotes,
  });

  factory OtaManifest.fromJson(Map<String, dynamic> j) => OtaManifest(
        version: j['version'] as String? ?? '',
        versionName: j['version_name'] as String? ?? '',
        buildNumber: (j['build_number'] as num?)?.toInt() ?? 0,
        commit: j['commit'] as String? ?? '',
        builtAt: j['built_at'] as String? ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        sha256: j['sha256'] as String? ?? '',
        url: j['url'] as String? ?? '',
        releaseNotes: j['release_notes'] as String? ?? '',
      );

  String get fullUrl =>
      url.startsWith('http') ? url : '$_otaBase$url';
}

/// Lightweight singleton cache so VersionChip can show a badge without
/// re-fetching on every build() call.
class OtaUpdateCache {
  OtaUpdateCache._();
  static final OtaUpdateCache instance = OtaUpdateCache._();

  OtaManifest? latestManifest;
  bool? updateAvailable;
  DateTime? checkedAt;

  bool get isStale {
    if (checkedAt == null) return true;
    return DateTime.now().difference(checkedAt!) > const Duration(minutes: 30);
  }

  void set(OtaManifest? m, bool available) {
    latestManifest = m;
    updateAvailable = available;
    checkedAt = DateTime.now();
  }
}

class OtaService {
  OtaService._();
  static final OtaService instance = OtaService._();

  Future<OtaManifest?> fetchLatest() async {
    try {
      final resp = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return OtaManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<({String currentVersion, int currentBuildNumber})>
      currentVersionInfo() async {
    final info = await PackageInfo.fromPlatform();
    return (
      currentVersion: info.version,
      currentBuildNumber: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  bool isUpdateAvailable(OtaManifest m, int currentBuildNumber) =>
      m.buildNumber > currentBuildNumber;

  /// Downloads the APK, verifies SHA-256, returns local file path.
  /// [onProgress] receives 0.0 – 1.0.
  Future<String> downloadApk(
    OtaManifest m,
    void Function(double progress) onProgress,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final dest = File('${tmpDir.path}/pulse-update.apk');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(m.fullUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} downloading APK');
      }

      final total = response.contentLength ?? m.size;
      final sink = dest.openWrite();
      final digest = AccumulatorSink<Digest>();
      final input = sha256.startChunkedConversion(digest);

      int received = 0;
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        input.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      });
      input.close();
      await sink.flush();
      await sink.close();

      final actualHash = digest.events.single.toString();
      if (actualHash != m.sha256) {
        await dest.delete();
        throw Exception(
            'SHA-256 mismatch: expected ${m.sha256}, got $actualHash');
      }

      onProgress(1.0);
      return dest.path;
    } finally {
      client.close();
    }
  }

  /// Fires Android's install intent. On web this is a no-op.
  Future<void> launchInstaller(String apkPath) async {
    if (kIsWeb) return;
    final result = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Failed to open installer: ${result.message}');
    }
  }

  /// Convenience: fetch + cache + compare. Returns updateAvailable flag.
  Future<bool> checkForUpdate() async {
    final cache = OtaUpdateCache.instance;
    if (!cache.isStale && cache.updateAvailable != null) {
      return cache.updateAvailable!;
    }
    final manifest = await fetchLatest();
    if (manifest == null) {
      return false;
    }
    final info = await currentVersionInfo();
    final available = isUpdateAvailable(manifest, info.currentBuildNumber);
    cache.set(manifest, available);
    return available;
  }
}
