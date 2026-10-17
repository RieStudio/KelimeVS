import 'package:shared_preferences/shared_preferences.dart';

abstract class ProfileRepository {
  Future<String?> getNickname();
  Future<void> setNickname(String nickname);
  Future<bool> hasNickname();
  Future<int> getCoins({int defaultCoins = 100});
  Future<void> setCoins(int coins);
  Future<bool> isNicknameSyncPending();
  Future<void> setNicknameSyncPending(bool pending);
  Future<void> clear();
}

class LocalProfileRepository implements ProfileRepository {
  static const String keyNickname = 'user_nickname';
  static const String keyCoins = 'user_coins';
  static const String keyNicknameSyncPending = 'user_nickname_sync_pending';

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

  @override
  Future<int> getCoins({int defaultCoins = 100}) async {
    final p = await _getPrefs();
    return p.getInt(keyCoins) ?? defaultCoins;
  }

  @override
  Future<void> setCoins(int coins) async {
    final p = await _getPrefs();
    await p.setInt(keyCoins, coins);
  }

  @override
  Future<bool> isNicknameSyncPending() async {
    final p = await _getPrefs();
    return p.getBool(keyNicknameSyncPending) ?? false;
  }

  @override
  Future<void> setNicknameSyncPending(bool pending) async {
    final p = await _getPrefs();
    if (pending) {
      await p.setBool(keyNicknameSyncPending, true);
    } else {
      await p.remove(keyNicknameSyncPending);
    }
  }

  @override
  Future<void> clear() async {
    final p = await _getPrefs();
    await p.remove(keyNickname);
    await p.remove(keyCoins);
    await p.remove(keyNicknameSyncPending);
  }
}
