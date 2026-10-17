import 'package:shared_preferences/shared_preferences.dart';

abstract class ProfileRepository {
  Future<String?> getNickname();
  Future<void> setNickname(String nickname);
  Future<bool> hasNickname();
}

class LocalProfileRepository implements ProfileRepository {
  static const String keyNickname = 'user_nickname';

  final SharedPreferences? prefs;

  const LocalProfileRepository({this.prefs});

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<String?> getNickname() async {
    final p = await _getPrefs();
    final name = p.getString(keyNickname)?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  @override
  Future<void> setNickname(String nickname) async {
    final p = await _getPrefs();
    await p.setString(keyNickname, nickname.trim());
  }

  @override
  Future<bool> hasNickname() async {
    final nick = await getNickname();
    return nick != null && nick.isNotEmpty;
  }
}
