import 'package:shared_preferences/shared_preferences.dart';

/// 應用程式設定。
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _kAutoSelect = 'auto_select_splits';
  static const _kAutoQueue = 'auto_continue_queue';
  static const _kSkipConfirm = 'allow_user_action_skip';
  static const _kUpdateOwnership = 'request_update_ownership';

  /// 自動勾選符合裝置的分割包（預設開）。
  bool autoSelectSplits = true;

  /// 佇列安裝成功後自動繼續下一個（預設開）。
  bool autoContinueQueue = true;

  /// Android 12+：更新時嘗試免使用者確認（僅當本應用為原安裝來源時系統才允許）。
  bool allowUserActionSkip = false;

  /// Android 14+：安裝時請求「更新擁有權」。
  bool requestUpdateOwnership = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    autoSelectSplits = p.getBool(_kAutoSelect) ?? true;
    autoContinueQueue = p.getBool(_kAutoQueue) ?? true;
    allowUserActionSkip = p.getBool(_kSkipConfirm) ?? false;
    requestUpdateOwnership = p.getBool(_kUpdateOwnership) ?? false;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoSelect, autoSelectSplits);
    await p.setBool(_kAutoQueue, autoContinueQueue);
    await p.setBool(_kSkipConfirm, allowUserActionSkip);
    await p.setBool(_kUpdateOwnership, requestUpdateOwnership);
  }
}
