import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/installer_channel.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import 'about_page.dart';

/// 設定：安裝偏好、權限管理、快取清理。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final _channel = InstallerChannel.instance;
  final _settings = SettingsStore.instance;
  PermissionState? _perm;
  DeviceInfo? _device;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final p = await _channel.getPermissionState();
      final d = await _channel.getDeviceInfo();
      if (!mounted) return;
      setState(() {
        _perm = p;
        _device = d;
      });
    } catch (_) {}
  }

  Future<void> _save() => _settings.save();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final sdk = _perm?.sdkInt ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionTitle('安裝偏好'),
          SwitchListTile(
            title: const Text('自動勾選建議的分割包'),
            subtitle: const Text('依裝置的 CPU 架構、螢幕密度與語言自動選擇',
                style: TextStyle(fontSize: 12)),
            value: _settings.autoSelectSplits,
            onChanged: (v) {
              setState(() => _settings.autoSelectSplits = v);
              _save();
            },
          ),
          SwitchListTile(
            title: const Text('批次安裝自動繼續'),
            subtitle: const Text('多檔佇列中，安裝成功後自動開始下一個',
                style: TextStyle(fontSize: 12)),
            value: _settings.autoContinueQueue,
            onChanged: (v) {
              setState(() => _settings.autoContinueQueue = v);
              _save();
            },
          ),
          if (sdk >= 31)
            SwitchListTile(
              title: const Text('更新時嘗試免確認'),
              subtitle: const Text(
                  '僅適用於「由本應用安裝過」的應用更新（Android 12+，由系統最終決定）',
                  style: TextStyle(fontSize: 12)),
              value: _settings.allowUserActionSkip,
              onChanged: (v) {
                setState(() => _settings.allowUserActionSkip = v);
                _save();
              },
            ),
          if (sdk >= 34)
            SwitchListTile(
              title: const Text('請求更新擁有權'),
              subtitle: const Text(
                  '安裝時成為該應用的更新來源，其他來源更新前會徵求確認（Android 14+）',
                  style: TextStyle(fontSize: 12)),
              value: _settings.requestUpdateOwnership,
              onChanged: (v) {
                setState(() => _settings.requestUpdateOwnership = v);
                _save();
              },
            ),

          _sectionTitle('權限'),
          _permTile(
            title: '安裝未知應用程式',
            subtitle: sdk >= 26
                ? '安裝 APK 的必要權限'
                : 'Android 7.x：於「安全性」設定開啟未知來源',
            granted: _perm?.canInstall,
            onRequest: () => _channel.requestInstallPermission(),
          ),
          if (sdk >= 30)
            _permTile(
              title: '所有檔案存取',
              subtitle: '寫入 OBB 資源檔（Android/obb）時需要',
              granted: _perm?.allFiles,
              onRequest: () => _channel.requestAllFilesPermission(),
            ),
          if (sdk >= 24 && sdk < 30)
            _permTile(
              title: '儲存空間',
              subtitle: '讀取安裝包與寫入 OBB 資源檔',
              granted: _perm?.legacyStorage,
              onRequest: () async {
                final status = await Permission.storage.request();
                if (status.isPermanentlyDenied) {
                  openAppSettings();
                }
                _refresh();
              },
            ),
          if (sdk >= 33)
            _permTile(
              title: '通知',
              subtitle: '顯示安裝完成 / 失敗通知',
              granted: _perm?.notifications,
              onRequest: () async {
                final status = await Permission.notification.request();
                if (status.isPermanentlyDenied) {
                  openAppSettings();
                }
                _refresh();
              },
            ),

          _sectionTitle('儲存空間'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: const Text('清除快取'),
            subtitle: const Text('刪除匯入的安裝包副本與匯出暫存檔',
                style: TextStyle(fontSize: 12)),
            onTap: () async {
              final freed = await _channel.clearCache();
              _toast('已釋放 ${formatBytes(freed)}');
            },
          ),

          _sectionTitle('關於'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('關於安裝大師'),
            subtitle: _device == null
                ? null
                : Text(
                    '本機：${androidVersionName(_device!.sdkInt)}'
                    '・${_device!.abis.join('、')}',
                    style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _permTile({
    required String title,
    required String subtitle,
    required bool? granted,
    required VoidCallback onRequest,
  }) {
    final ok = granted == true;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: ok ? BrandColors.success : BrandColors.danger,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: ok
          ? null
          : FilledButton.tonal(
              onPressed: onRequest,
              child: const Text('授權'),
            ),
    );
  }
}
