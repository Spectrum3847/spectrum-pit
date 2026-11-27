import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

class TeamTbaConfig implements TbaConfig {
  TeamTbaConfig({
    this._fetchRemote,
    Future<SharedPreferences> Function()? prefsLoader,
    this._fallback = const CompileTimeTbaConfig(),
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String prefsKey = 'tba_team_api_key';

  final Future<String?> Function()? _fetchRemote;
  final Future<SharedPreferences> Function() _prefsLoader;
  final TbaConfig _fallback;

  @override
  Future<String?> resolveApiKey() async {
    final prefs = await _prefsLoader();
    final fetch = _fetchRemote;
    if (fetch != null) {
      try {
        final remote = (await fetch())?.trim();
        if (remote != null && remote.isNotEmpty) {
          await prefs.setString(prefsKey, remote);
          return remote;
        }
        if (remote != null) {
          await prefs.remove(prefsKey);
        }
      } catch (_) {}
    }
    final kept = prefs.getString(prefsKey);
    if (kept != null && kept.isNotEmpty) return kept;
    return _fallback.resolveApiKey();
  }
}
