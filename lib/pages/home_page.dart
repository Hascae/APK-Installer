import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/history_store.dart';
import '../services/installer_channel.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import 'apps_page.dart';
import 'history_page.dart';
import 'install_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _channel = InstallerChannel.instance;

  DeviceInfo? _device;
  PermissionState? _perm;
  List<HistoryEntry> _recent = [];
  StreamSubscription<NativeEvent>? _sub;
  bool _busyImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _refreshState();
    // Android 13+ 通知權限：首次啟動時申請
    if ((_perm?.sdkInt ?? 0) >= 33 && !(_perm?.notifications ?? true)) {
      await Permission.notification.request();
      await _refreshState();
    }
    // 監聽執行中由外部帶入的檔案
    _sub = _channel.events.listen((e) {
      if (e.type == 'new_file') {
        final uri = e.data['uri'] as String?;
        if (uri != null) _openExternalUri(uri);
      }
    });
    // 冷啟動時由檔案管理器 / 分享帶入的檔案
    final pending = await _channel.takePendingFile();
    if (pending != null) {
      _openExternalUri(pending);
    }
  }

  Future<void> _refreshState() async {
    try {
      final device = await _channel.getDeviceInfo();
      final perm = await _channel.getPermissionState();
      final recent = await HistoryStore.instance.load();
      if (!mounted) return;
      setState(() {
        _device = device;
        _perm = perm;
        _recent = recent.take(3).toList();
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  // ---------- 開啟檔案 ----------

  Future<void> _pickAndInstall() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['apk', 'apkm', 'xapk', 'apks', 'zip'],
        allowMultiple: true,
      );
    } catch (_) {
      // 個別機型的檔案選擇器不支援自訂副檔名 → 退回不過濾
      try {
        result = await FilePicker.platform.pickFiles(allowMultiple: true);
      } catch (e) {
        _toast('無法開啟檔案選擇器：$e');
        return;
      }
    }
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) {
      _toast('無法讀取所選檔案');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InstallPage(paths: paths)),
    );
    _refreshState();
  }

  Future<void> _openExternalUri(String uri) async {
    if (_busyImporting) return;
    setState(() => _busyImporting = true);
    try {
      final imported = await _channel.importUri(uri);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InstallPage(paths: [imported.path])),
      );
    } catch (e) {
      _toast('讀取檔案失敗：$e');
    } finally {
      if (mounted) setState(() => _busyImporting = false);
      _refreshState();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needInstallPerm = _perm != null && !_perm!.canInstall;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 24),
            // 品牌標頭
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandLogo(size: 56),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('安裝大師',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        )),
                    Text('APK・APKM・XAPK・APKS 安裝器',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface.withOpacity(0.55),
                        )),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (needInstallPerm) _installPermissionCard(),

            // 主要動作
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BigActionButton(
                busy: _busyImporting,
                onTap: _pickAndInstall,
              ),
            ),
            const SizedBox(height: 12),

            // 功能入口
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _NavCard(
                      title: '應用管理',
                      subtitle: '匯出 / 解除安裝',
                      icon: Icons.apps_rounded,
                      onTap: () => _push(const AppsPage()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NavCard(
                      title: '安裝歷史',
                      subtitle: '成功與失敗紀錄',
                      icon: Icons.history_rounded,
                      onTap: () => _push(const HistoryPage()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NavCard(
                      title: '設定',
                      subtitle: '權限與偏好',
                      icon: Icons.tune_rounded,
                      onTap: () => _push(const SettingsPage()),
                    ),
                  ),
                ],
              ),
            ),

            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('最近活動',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withOpacity(0.7),
                    )),
              ),
              const SizedBox(height: 4),
              ..._recent.map((h) => ListTile(
                    leading: Icon(
                      h.success
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: h.success ? BrandColors.success : BrandColors.danger,
                    ),
                    title: Text(h.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${h.kind == 'uninstall' ? '解除安裝' : '安裝'}'
                      '${h.success ? '成功' : '失敗'}・${formatTime(h.time)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _push(const HistoryPage()),
                  )),
            ],

            if (_device != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  '${_device!.brand} ${_device!.model}・'
                  '${androidVersionName(_device!.sdkInt)}・'
                  '${_device!.abis.isNotEmpty ? _device!.abis.first : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _installPermissionCard() {
    final sdk = _perm?.sdkInt ?? 26;
    return Card(
      color: BrandColors.warning.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_rounded, color: BrandColors.warning),
                SizedBox(width: 8),
                Text('需要安裝權限',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sdk >= 26
                  ? '請允許「安裝大師」安裝未知應用程式，才能執行安裝。'
                  : '請在系統設定中開啟「未知來源」，才能執行安裝。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                await _channel.requestInstallPermission();
              },
              child: const Text('前往授權'),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _refreshState();
  }
}

/// 首頁主按鈕：大面積漸層卡片。
class _BigActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;

  const _BigActionButton({required this.onTap, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E7490), Color(0xFF4338CA)],
          ),
        ),
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Row(
              children: [
                busy
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3),
                      )
                    : const BrandLogo(size: 44, withBackground: false),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(busy ? '正在讀取檔案…' : '選擇安裝包',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                      const SizedBox(height: 4),
                      const Text(
                        '支援 APK・APKM・XAPK・APKS・ZIP，可多選批次安裝',
                        style: TextStyle(fontSize: 12.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white70, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, size: 26, color: scheme.primary),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurface.withOpacity(0.5),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
