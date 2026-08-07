import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import 'http_timeout_client.dart';

class DesktopUpdateInfo {
  const DesktopUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.repository,
    this.appImageUrl,
    this.expectedSha256,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final String repository;

  final String? appImageUrl;

  final String? expectedSha256;
}

class DesktopUpdateService {
  DesktopUpdateService({
    http.Client? client,
    Future<String> Function()? currentVersionLoader,
    List<String>? repositories,
  }) : _client = client ?? TimeoutHttpClient(),
       _currentVersionLoader = currentVersionLoader ?? _defaultVersionLoader,
       _repositories = repositories ?? _defaultRepositories;

  static const List<String> _defaultRepositories = <String>[
    'Spectrum3847/spectrum-pit',
  ];

  final http.Client _client;
  final Future<String> Function() _currentVersionLoader;
  final List<String> _repositories;

  Future<DesktopUpdateInfo?> checkForUpdate() async {
    final currentRaw = (await _currentVersionLoader()).trim();
    final current = _parseVersion(currentRaw);
    if (current == null) {
      return null;
    }

    Object? transportFailure;
    StackTrace? transportStackTrace;
    for (final repository in _repositories) {
      final _ReleaseSnapshot? release;
      try {
        release = await _loadLatestRelease(repository);
      } catch (error, stackTrace) {
        transportFailure ??= error;
        transportStackTrace ??= stackTrace;
        continue;
      }
      if (release == null) {
        continue;
      }
      if (release.version.compareTo(current) > 0) {
        return DesktopUpdateInfo(
          currentVersion: currentRaw,
          latestVersion: release.rawTag,
          releaseUrl: release.url,
          repository: repository,
          appImageUrl: release.appImageUrl,
          expectedSha256: release.expectedSha256,
        );
      }
    }
    if (transportFailure != null) {
      Error.throwWithStackTrace(transportFailure, transportStackTrace!);
    }
    return null;
  }

  Future<_ReleaseSnapshot?> _loadLatestRelease(String repository) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
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
    final url = Uri.tryParse(htmlUrlRaw);
    if (version == null || url == null) {
      return null;
    }
    final asset = _appImageAsset(decoded['assets']);
    return _ReleaseSnapshot(
      version: version,
      rawTag: tagName,
      url: url,
      appImageUrl: asset.url,
      expectedSha256: asset.digest,
    );
  }

  static ({String? url, String? digest}) _appImageAsset(dynamic assets) {
    if (assets is! List) return (url: null, digest: null);
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String? ?? '';
        final dl = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('.AppImage') && dl.isNotEmpty) {
          final rawDigest = asset['digest'] as String?;
          final digest = rawDigest?.replaceFirst(RegExp('^sha256:'), '');
          return (url: dl, digest: digest);
        }
      }
    }
    return (url: null, digest: null);
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
    this.appImageUrl,
    this.expectedSha256,
  });

  final Version version;
  final String rawTag;
  final Uri url;
  final String? appImageUrl;
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
