import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_provider.dart'; // for sharedPreferencesProvider

class AppPrefs {
  final bool notifications;
  final bool dataSaver;
  const AppPrefs({this.notifications = true, this.dataSaver = false});
  AppPrefs copyWith({bool? notifications, bool? dataSaver}) => AppPrefs(
        notifications: notifications ?? this.notifications,
        dataSaver: dataSaver ?? this.dataSaver,
      );
}

class AppPrefsNotifier extends StateNotifier<AppPrefs> {
  final SharedPreferences _prefs;
  AppPrefsNotifier(this._prefs)
      : super(AppPrefs(
          notifications: _prefs.getBool('pref_notifications') ?? true,
          dataSaver: _prefs.getBool('pref_data_saver') ?? false,
        ));

  void setNotifications(bool v) {
    state = state.copyWith(notifications: v);
    _prefs.setBool('pref_notifications', v);
    // NOTE: to fully honor this, gate FCM subscription on this flag in main.dart
    // (see S5-DASH note). The toggle persists regardless.
  }

  void setDataSaver(bool v) {
    state = state.copyWith(dataSaver: v);
    _prefs.setBool('pref_data_saver', v);
  }
}

final appPrefsProvider =
    StateNotifierProvider<AppPrefsNotifier, AppPrefs>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppPrefsNotifier(prefs);
});
