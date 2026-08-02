import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class DesktopUpdateInfo {
  const DesktopUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.repository,
    this.appImageUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final String repository;

  final String? appImageUrl;
}

class DesktopUpdateService {
  DesktopUpdateService({
    http.Client? client,
    Future<String> Function()? currentVersionLoader,
    List<String>? repositories,
  }) : _client = client ?? http.Client(),
       _currentVersionLoader = currentVersionLoader ?? _defaultVersionLoader,
       _repositories = repositories ?? _defaultRepositories;

  static const List<String> _defaultRepositories = <String>[
    'Spectrum3847/spectrum-pit-releases',
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

    for (final repository in _repositories) {
      final release = await _loadLatestRelease(repository);
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
        );
      }
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
    final decoded = jsonDecode(response.body);
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
    return _ReleaseSnapshot(
      version: version,
      rawTag: tagName,
      url: url,
      appImageUrl: _appImageAssetUrl(decoded['assets']),
    );
  }

  static String? _appImageAssetUrl(dynamic assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String? ?? '';
        final dl = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('.AppImage') && dl.isNotEmpty) return dl;
      }
    }
    return null;
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
  });

  final _SemanticVersion version;
  final String rawTag;
  final Uri url;
  final String? appImageUrl;
}

_SemanticVersion? _parseVersion(String input) {
  final normalized = input.trim().replaceFirst(RegExp(r'^[vV]'), '');
  if (normalized.isEmpty) {
    return null;
  }
  final core = normalized.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  if (parts.length < 3) {
    return null;
  }
  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  final patch = int.tryParse(parts[2]);
  if (major == null || minor == null || patch == null) {
    return null;
  }
  return _SemanticVersion(major: major, minor: minor, patch: patch);
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_SemanticVersion other) {
    final majorDiff = major.compareTo(other.major);
    if (majorDiff != 0) {
      return majorDiff;
    }
    final minorDiff = minor.compareTo(other.minor);
    if (minorDiff != 0) {
      return minorDiff;
    }
    return patch.compareTo(other.patch);
  }
}
