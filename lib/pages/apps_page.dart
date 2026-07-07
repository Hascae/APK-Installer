import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/installer_channel.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// 應用管理：檢視已安裝應用、匯出 APK / APKS、解除安裝。
class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final _channel = InstallerChannel.instance;
  final _iconCache = <String, Uint8List?>{};
  final _searchCtrl = TextEditingController();

  List<InstalledApp> _apps = [];
  bool _loading = true;
  bool _includeSystem = false;
  String _query = '';
  StreamSubscription<NativeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // 解除安裝完成後自動重新整理
    _sub = _channel.events.listen((e) {
      if (e.type == 'result' && e.data['kind'] == 'uninstall') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await _channel.listApps(includeSystem: _includeSystem);
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('讀取應用清單失敗：$e');
    }
  }

  List<InstalledApp> get _filtered {
    if (_query.isEmpty) return _apps;
    final q = _query.toLowerCase();
    return _apps
        .where((a) =>
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
        .toList();
  }

  Future<Uint8List?> _icon(String pkg) async {
    if (_iconCache.containsKey(pkg)) return _iconCache[pkg];
    final bytes = await _channel.getAppIcon(pkg);
    _iconCache[pkg] = bytes;
    return bytes;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- 動作 ----------

  void _showActions(InstalledApp app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(app.label,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${app.package}\n版本 ${app.versionName}（${app.versionCode}）'
                '・${formatBytes(app.apkSize)}'
                '${app.splits > 0 ? '・${app.splits} 個分割包' : ''}\n'
                '安裝於 ${formatTime(app.firstInstall)}・更新於 ${formatTime(app.lastUpdate)}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('開啟應用'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await _channel.openApp(app.package);
                if (!ok) _toast('此應用沒有可開啟的介面');
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(app.splits > 0 ? '匯出為 APKS（含分割包）' : '匯出 APK'),
              subtitle: const Text('匯出後可分享或另存至任何位置',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () {
                Navigator.of(ctx).pop();
                _export(app);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('系統應用資訊'),
              onTap: () {
                Navigator.of(ctx).pop();
                _channel.openAppSettings(app.package);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: BrandColors.danger),
              title: const Text('解除安裝',
                  style: TextStyle(color: BrandColors.danger)),
              enabled: !app.system,
              onTap: () async {
                Navigator.of(ctx).pop();
                await _channel.uninstall(app.package, app.label);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _export(InstalledApp app) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('正在匯出…')),
          ],
        ),
      ),
    );
    try {
      final r = await _channel.exportApp(app.package);
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度框
      await Share.shareXFiles(
        [XFile(r.path)],
        text: '${app.label} ${app.versionName}',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('匯出失敗：$e');
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('應用管理'),
        actions: [
          Row(
            children: [
              const Text('系統應用', style: TextStyle(fontSize: 12)),
              Switch(
                value: _includeSystem,
                onChanged: (v) {
                  setState(() => _includeSystem = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜尋應用名稱或套件名稱',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const EmptyState(message: '沒有符合條件的應用')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _appTile(list[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _appTile(InstalledApp app) {
    return ListTile(
      leading: FutureBuilder<Uint8List?>(
        future: _icon(app.package),
        builder: (_, snap) => AppIconImage(bytes: snap.data, size: 44),
      ),
      title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${app.versionName}・${formatBytes(app.apkSize)}'
        '${app.splits > 0 ? '・${app.splits} 個分割包' : ''}'
        '${app.system ? '・系統' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () => _showActions(app),
    );
  }
}
