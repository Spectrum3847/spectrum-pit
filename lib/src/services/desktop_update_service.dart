import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_timeout_client.dart';
import 'desktop_self_update_service.dart' show DesktopSelfUpdatePlatform;

enum DesktopUpdateChannel {
  stable,
  nightly;

  static DesktopUpdateChannel fromName(String? name) =>
      name == nightly.name ? nightly : stable;
}

class DesktopUpdateInfo {
  const DesktopUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.repository,
    this.assetUrl,
    this.expectedSha256,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final String repository;

  final String? assetUrl;

  final String? expectedSha256;
}

class DesktopUpdateService {
  DesktopUpdateService({
    http.Client? client,
    Future<String> Function()? currentVersionLoader,
    List<String>? repositories,
    Future<SharedPreferences> Function()? prefs,
    DesktopSelfUpdatePlatform Function()? platformLoader,
    String? buildTimestamp,
    DateTime Function()? now,
  }) : _client = client ?? TimeoutHttpClient(),
       _currentVersionLoader = currentVersionLoader ?? _defaultVersionLoader,
       _repositories = repositories ?? _defaultRepositories,
       _prefsLoader = prefs ?? SharedPreferences.getInstance,
       _platform = platformLoader ?? DesktopSelfUpdatePlatform.detect,
       _buildTimestamp = buildTimestamp ?? _envBuildTimestamp,
       _now = now ?? DateTime.now;

  static const List<String> _defaultRepositories = <String>[
    'Spectrum3847/spectrum-pit',
  ];

  static const String channelKey = 'desktop_update_channel';

  static const String _envBuildTimestamp = String.fromEnvironment(
    'BUILD_TIMESTAMP',
  );

  static const Duration nightlyFreshness = Duration(hours: 25);

  final http.Client _client;
  final Future<String> Function() _currentVersionLoader;
  final List<String> _repositories;
  final Future<SharedPreferences> Function() _prefsLoader;
  final DesktopSelfUpdatePlatform Function() _platform;
  final String _buildTimestamp;
  final DateTime Function() _now;

  Future<DesktopUpdateChannel> currentChannel() async {
    final prefs = await _prefsLoader();
    return DesktopUpdateChannel.fromName(prefs.getString(channelKey));
  }

  Future<void> setChannel(DesktopUpdateChannel channel) async {
    final prefs = await _prefsLoader();
    await prefs.setString(channelKey, channel.name);
  }

  Future<DesktopUpdateInfo?> checkForUpdate({
    DesktopUpdateChannel? channel,
    bool ignoreVersionGate = false,
  }) async {
    final currentRaw = (await _currentVersionLoader()).trim();
    final current = _parseVersion(currentRaw);
    if (current == null) {
      return null;
    }
    final effectiveChannel = channel ?? await currentChannel();
    if (effectiveChannel == DesktopUpdateChannel.nightly) {
      return _checkNightly(currentRaw, ignoreVersionGate: ignoreVersionGate);
    }
    return _checkStable(
      currentRaw,
      current,
      ignoreVersionGate: ignoreVersionGate,
    );
  }

  Future<DesktopUpdateInfo?> _checkStable(
    String currentRaw,
    Version current, {
    required bool ignoreVersionGate,
  }) async {
    Object? transportFailure;
    StackTrace? transportStackTrace;
    for (final repository in _repositories) {
      final _ReleaseSnapshot? release;
      try {
        release = await _loadRelease(repository, 'releases/latest');
      } catch (error, stackTrace) {
        transportFailure ??= error;
        transportStackTrace ??= stackTrace;
        continue;
      }
      if (release == null || release.version == null) {
        continue;
      }
      final isNewer =
          ignoreVersionGate || release.version!.compareTo(current) > 0;
      if (isNewer) {
        return DesktopUpdateInfo(
          currentVersion: currentRaw,
          latestVersion: release.rawTag,
          releaseUrl: release.url,
          repository: repository,
          assetUrl: release.assetUrl,
          expectedSha256: release.expectedSha256,
        );
      }
    }
    if (transportFailure != null) {
      Error.throwWithStackTrace(transportFailure, transportStackTrace!);
    }
    return null;
  }

  Future<DesktopUpdateInfo?> _checkNightly(
    String currentRaw, {
    required bool ignoreVersionGate,
  }) async {
    if (!ignoreVersionGate && _isFreshNightly()) {
      return null;
    }
    final release = await _loadRelease(
      _repositories.first,
      'releases/tags/nightly',
      requireVersion: false,
    );
    if (release == null) {
      return null;
    }
    return DesktopUpdateInfo(
      currentVersion: currentRaw,
      latestVersion: release.rawTag,
      releaseUrl: release.url,
      repository: _repositories.first,
      assetUrl: release.assetUrl,
      expectedSha256: release.expectedSha256,
    );
  }

  bool _isFreshNightly() {
    final built = DateTime.tryParse(_buildTimestamp.trim());
    if (built == null) {
      return false;
    }
    return _now().toUtc().difference(built.toUtc()) < nightlyFreshness;
  }

  Future<_ReleaseSnapshot?> _loadRelease(
    String repository,
    String urlPath, {
    bool requireVersion = true,
  }) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$repository/$urlPath'),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final tagName = (decoded['tag_name'] as String? ?? '').trim();
    final htmlUrlRaw = (decoded['html_url'] as String? ?? '').trim();
    if (tagName.isEmpty || htmlUrlRaw.isEmpty) {
      return null;
    }
    final version = _parseVersion(tagName);
    if (requireVersion && version == null) {
      return null;
    }
    final url = Uri.tryParse(htmlUrlRaw);
    if (url == null) {
      return null;
    }
    final asset = _selfUpdateAsset(decoded['assets'], _platform());
    return _ReleaseSnapshot(
      version: version,
      rawTag: tagName,
      url: url,
      assetUrl: asset.url,
      expectedSha256: asset.digest,
    );
  }

  static ({String? url, String? digest}) _selfUpdateAsset(
    dynamic assets,
    DesktopSelfUpdatePlatform platform,
  ) {
    if (assets is! List) return (url: null, digest: null);
    Map<String, dynamic>? best;
    DateTime bestCreated = DateTime.fromMillisecondsSinceEpoch(0);
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      final dl = asset['browser_download_url'] as String? ?? '';
      final matches = switch (platform) {
        DesktopSelfUpdatePlatform.linux => name.endsWith('.AppImage'),
        DesktopSelfUpdatePlatform.windows =>
          name.endsWith('.zip') && name.contains('windows'),
        DesktopSelfUpdatePlatform.macos =>
          name.endsWith('.zip') && name.contains('macos'),
      };
      if (!matches || dl.isEmpty) continue;
      final createdRaw = asset['created_at'] as String?;
      final created =
          (createdRaw == null ? null : DateTime.tryParse(createdRaw)) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (best == null || created.isAfter(bestCreated)) {
        best = asset;
        bestCreated = created;
      }
    }
    if (best == null) return (url: null, digest: null);
    final rawDigest = best['digest'] as String?;
    final digest = rawDigest?.replaceFirst(RegExp('^sha256:'), '');
    return (url: best['browser_download_url'] as String?, digest: digest);
  }

  static Future<String> _defaultVersionLoader() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}

class _ReleaseSnapshot {
  const _ReleaseSnapshot({
    required this.version,
    required this.rawTag,
    required this.url,
    this.assetUrl,
    this.expectedSha256,
  });

  final Version? version;
  final String rawTag;
  final Uri url;
  final String? assetUrl;
  final String? expectedSha256;
}

Version? _parseVersion(String input) {
  final normalized = input.trim().replaceFirst(RegExp(r'^[vV]'), '');
  if (normalized.isEmpty) {
    return null;
  }
  try {
    return Version.parse(normalized);
  } on FormatException {
    return null;
  }
}
