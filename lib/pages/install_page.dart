import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/history_store.dart';
import '../services/installer_channel.dart';
import '../services/settings_store.dart';
import '../services/split_selector.dart';
import '../theme.dart';
import '../widgets/brand.dart';

enum _Phase {
  analyzing,
  analyzeError,
  ready,
  installingObb,
  copying,
  waitingConfirm,
  success,
  failure,
}

/// 安裝流程頁：解析 → 選擇分割包 → 安裝 → 結果。
/// 支援多檔佇列（批次安裝）。
class InstallPage extends StatefulWidget {
  final List<String> paths;

  const InstallPage({super.key, required this.paths});

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> with WidgetsBindingObserver {
  final _channel = InstallerChannel.instance;
  final _settings = SettingsStore.instance;

  int _index = 0;
  _Phase _phase = _Phase.analyzing;
  ArchiveInfo? _info;
  DeviceInfo? _device;
  PermissionState? _perm;
  List<String> _warnings = [];
  String _error = '';
  String _resultMessage = '';
  bool _installObb = true;
  bool _busy = false;

  int _copyDone = 0;
  int _copyTotal = 0;

  StreamSubscription<NativeEvent>? _sub;
  Timer? _autoAdvance;

  String get _currentPath => widget.paths[_index];
  bool get _hasNext => _index < widget.paths.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _channel.events.listen(_onEvent);
    _prepare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _autoAdvance?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPerm();
    }
  }

  Future<void> _refreshPerm() async {
    try {
      final p = await _channel.getPermissionState();
      if (mounted) setState(() => _perm = p);
    } catch (_) {}
  }

  // ---------- 解析 ----------

  Future<void> _prepare() async {
    setState(() {
      _phase = _Phase.analyzing;
      _info = null;
      _warnings = [];
      _error = '';
      _resultMessage = '';
      _copyDone = 0;
      _copyTotal = 0;
      _installObb = true;
    });
    try {
      _device ??= await _channel.getDeviceInfo();
      _perm = await _channel.getPermissionState();
      final info = await _channel.analyze(_currentPath);
      final warnings = <String>[];

      if (info.isBundle && _settings.autoSelectSplits) {
        warnings.addAll(SplitSelector.autoSelect(info.splits, _device!));
      } else if (info.isBundle) {
        for (final s in info.splits) {
          s.selected = true;
        }
      }

      if (info.minSdk > 0 && info.minSdk > _device!.sdkInt) {
        warnings.add('此應用最低需要 ${androidVersionName(info.minSdk)}，'
            '高於本機（${androidVersionName(_device!.sdkInt)}），安裝將會失敗');
      }
      final inst = info.installed;
      if (inst != null) {
        if (info.versionCode < inst.versionCode) {
          warnings.add('這是降級安裝（已安裝 ${inst.versionName}，'
              '欲安裝 ${info.versionName}）。系統通常會拒絕，建議先解除安裝舊版');
        }
        if (inst.signatureMatch == false) {
          warnings.add('簽章不一致：安裝包與已安裝版本由不同金鑰簽署，'
              '直接安裝會失敗，需先解除安裝原版本（資料將遺失）');
        }
      }

      if (!mounted) return;
      setState(() {
        _info = info;
        _warnings = warnings;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('PlatformException(native_error, ', '')
            .replaceFirst(RegExp(r', null, null\)$'), '');
        _phase = _Phase.analyzeError;
      });
    }
  }

  // ---------- 事件 ----------

  void _onEvent(NativeEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'copy':
        setState(() {
          _copyDone = (e.data['done'] as num?)?.toInt() ?? 0;
          _copyTotal = (e.data['total'] as num?)?.toInt() ?? 0;
          _phase = _Phase.copying;
        });
      case 'obb':
        setState(() {
          _copyDone = (e.data['done'] as num?)?.toInt() ?? 0;
          _copyTotal = (e.data['total'] as num?)?.toInt() ?? 0;
          _phase = _Phase.installingObb;
        });
      case 'state':
        final phase = e.data['phase'] as String?;
        if (phase == 'pending_user' || phase == 'committing') {
          setState(() => _phase = _Phase.waitingConfirm);
        }
      case 'result':
        _onResult(e.data);
    }
  }

  Future<void> _onResult(Map<dynamic, dynamic> data) async {
    final kind = data['kind'] as String? ?? '';
    final pkg = data['package'] as String? ?? '';
    final success = data['success'] as bool? ?? false;
    final message = data['message'] as String? ?? '';
    final info = _info;
    if (info == null || pkg != info.packageName) return;

    if (kind == 'uninstall') {
      // 「先解除安裝舊版」流程完成 → 重新解析
      await HistoryStore.instance.add(HistoryEntry(
        time: DateTime.now().millisecondsSinceEpoch,
        package: pkg,
        label: info.label,
        versionName: info.installed?.versionName ?? '',
        kind: 'uninstall',
        success: success,
        message: message,
      ));
      if (success) {
        _toast('已解除安裝舊版');
        _prepare();
      } else if (message.isNotEmpty) {
        _toast('解除安裝失敗：$message');
      }
      return;
    }

    await HistoryStore.instance.add(HistoryEntry(
      time: DateTime.now().millisecondsSinceEpoch,
      package: pkg,
      label: info.label,
      versionName: info.versionName,
      kind: 'install',
      success: success,
      message: message,
    ));
    if (!mounted) return;
    setState(() {
      _resultMessage = message;
      _phase = success ? _Phase.success : _Phase.failure;
      _busy = false;
    });
    if (success && _hasNext && _settings.autoContinueQueue) {
      _autoAdvance = Timer(const Duration(seconds: 2), _next);
    }
  }

  // ---------- 動作 ----------

  Future<void> _startInstall() async {
    final info = _info;
    if (info == null || _busy) return;

    // 安裝權限
    await _refreshPerm();
    if (!mounted) return;
    if (_perm != null && !_perm!.canInstall) {
      _showInstallPermissionDialog();
      return;
    }

    // OBB 需要儲存空間權限
    final obbEntries = info.obbs.map((o) => o.entry).toList();
    if (_installObb && obbEntries.isNotEmpty) {
      final p = _perm;
      if (p != null && ((p.sdkInt >= 30 && !p.allFiles) ||
          (p.sdkInt < 30 && !p.legacyStorage))) {
        final go = await _confirm(
          '需要儲存空間權限',
          '安裝 OBB 資源檔需要「所有檔案存取」權限（寫入 Android/obb）。要前往授權嗎？\n\n'
          '也可以選擇略過 OBB，僅安裝 APK。',
          okText: '前往授權',
          cancelText: '略過 OBB',
        );
        if (go == true) {
          if (p.sdkInt >= 30) {
            await _channel.requestAllFilesPermission();
          }
          return; // 使用者回來後再按一次安裝
        } else {
          setState(() => _installObb = false);
        }
      }
    }

    setState(() {
      _busy = true;
      _copyDone = 0;
      _copyTotal = 0;
    });

    try {
      // 1. OBB
      if (_installObb && obbEntries.isNotEmpty) {
        setState(() => _phase = _Phase.installingObb);
        final r = await _channel.installObb(
          path: info.path,
          entries: obbEntries,
          packageName: info.packageName,
        );
        if (!r.ok && mounted) {
          _toast(r.message.isEmpty ? 'OBB 複製失敗，將僅安裝 APK' : r.message);
        }
      }

      // 2. APK / 分割包
      setState(() => _phase = _Phase.copying);
      List<String>? entries;
      if (info.isBundle) {
        entries = info.splits.where((s) => s.selected).map((s) => s.entry).toList();
        if (entries.isEmpty) {
          _toast('請至少選擇一個 APK');
          setState(() {
            _busy = false;
            _phase = _Phase.ready;
          });
          return;
        }
      }
      final inst = info.installed;
      final allowSkip = _settings.allowUserActionSkip && inst != null;
      await _channel.install(
        path: info.path,
        entries: entries,
        packageName: info.packageName,
        appLabel: info.label,
        allowUserActionSkip: allowSkip,
        requestUpdateOwnership: _settings.requestUpdateOwnership,
      );
      // 之後由事件流推進（等待確認 → 結果）
      if (mounted && _phase == _Phase.copying) {
        setState(() => _phase = _Phase.waitingConfirm);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultMessage = '$e';
        _phase = _Phase.failure;
        _busy = false;
      });
    }
  }

  Future<void> _uninstallOld() async {
    final info = _info;
    if (info == null) return;
    final ok = await _confirm(
      '解除安裝舊版',
      '將解除安裝「${info.label}」目前的版本，其應用資料可能一併移除。確定繼續嗎？',
      okText: '解除安裝',
      destructive: true,
    );
    if (ok == true) {
      await _channel.uninstall(info.packageName, info.label);
    }
  }

  void _next() {
    _autoAdvance?.cancel();
    if (!_hasNext) return;
    setState(() => _index++);
    _prepare();
  }

  void _showInstallPermissionDialog() {
    final sdk = _perm?.sdkInt ?? 26;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要安裝權限'),
        content: Text(sdk >= 26
            ? '請允許「安裝大師」安裝未知應用程式。授權後回到本頁，再按一次「安裝」即可。'
            : '請在「設定 → 安全性」開啟「未知來源」。開啟後回到本頁，再按一次「安裝」即可。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _channel.requestInstallPermission();
            },
            child: const Text('前往授權'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(
    String title,
    String message, {
    String okText = '確定',
    String cancelText = '取消',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelText),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: BrandColors.danger)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final queueLabel =
        widget.paths.length > 1 ? '（第 ${_index + 1} / ${widget.paths.length} 個）' : '';
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('安裝$queueLabel')),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.analyzing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在分析安裝包…'),
            ],
          ),
        );
      case _Phase.analyzeError:
        return _errorView();
      case _Phase.installingObb:
      case _Phase.copying:
      case _Phase.waitingConfirm:
        return _progressView();
      case _Phase.success:
        return _resultView(success: true);
      case _Phase.failure:
        return _resultView(success: false);
      case _Phase.ready:
        return _readyView();
    }
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.broken_image_rounded,
              size: 64, color: BrandColors.danger),
          const SizedBox(height: 16),
          const Text('無法解析這個檔案',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 24),
          if (_hasNext)
            FilledButton(onPressed: _next, child: const Text('略過，處理下一個')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _progressView() {
    final info = _info!;
    String label;
    switch (_phase) {
      case _Phase.installingObb:
        label = '正在複製 OBB 資源檔…';
      case _Phase.copying:
        label = '正在寫入安裝資料…';
      default:
        label = '等待系統確認安裝…';
    }
    final showBar = _phase != _Phase.waitingConfirm && _copyTotal > 0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppIconImage(bytes: info.iconBytes, size: 80)),
          const SizedBox(height: 16),
          Center(
            child: Text(info.label,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 32),
          if (showBar) ...[
            LinearProgressIndicator(
              value: (_copyDone / _copyTotal).clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${formatBytes(_copyDone)} / ${formatBytes(_copyTotal)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ] else
            const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(child: Text(label)),
          if (_phase == _Phase.waitingConfirm) ...[
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '若未出現確認視窗，請下拉通知列點選確認',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultView({required bool success}) {
    final info = _info!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 72,
            color: success ? BrandColors.success : BrandColors.danger,
          ),
          const SizedBox(height: 16),
          Text(
            success ? '安裝成功' : '安裝失敗',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            success ? '${info.label} ${info.versionName}' : _resultMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          if (success) ...[
            FilledButton(
              onPressed: () => _channel.openApp(info.packageName),
              child: const Text('開啟應用'),
            ),
            const SizedBox(height: 8),
            if (_hasNext)
              FilledButton.tonal(
                onPressed: _next,
                child: Text(_settings.autoContinueQueue
                    ? '繼續安裝下一個（即將自動繼續）'
                    : '繼續安裝下一個'),
              ),
          ] else ...[
            FilledButton(
              onPressed: () {
                setState(() => _phase = _Phase.ready);
              },
              child: const Text('返回重試'),
            ),
            const SizedBox(height: 8),
            if (info.installed != null)
              OutlinedButton(
                onPressed: _uninstallOld,
                child: const Text('先解除安裝舊版'),
              ),
            if (_hasNext) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _next, child: const Text('略過，處理下一個')),
            ],
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _readyView() {
    final info = _info!;
    final selectedSize = info.isBundle
        ? info.splits
            .where((s) => s.selected)
            .fold<int>(0, (a, b) => a + b.size)
        : info.fileSize;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SizedBox(height: 8),
              _appInfoCard(info),
              if (_warnings.isNotEmpty) _warningsCard(),
              if (info.isBundle) ..._splitSections(info),
              if (info.obbs.isNotEmpty) _obbCard(info),
            ],
          ),
        ),
        // 底部安裝列
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.installed == null
                            ? '全新安裝'
                            : (info.versionCode >=
                                    info.installed!.versionCode
                                ? '更新安裝'
                                : '降級安裝'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '安裝大小約 ${formatBytes(selectedSize)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _startInstall,
                  child: Text(_busy ? '安裝中…' : '安裝'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _appInfoCard(ArchiveInfo info) {
    final inst = info.installed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIconImage(bytes: info.iconBytes, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(info.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                FileTypeBadge(fileName: info.fileName),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _kv('版本', '${info.versionName}（${info.versionCode}）'),
            if (inst != null)
              _kv('已安裝版本', '${inst.versionName}（${inst.versionCode}）'),
            _kv('系統需求', '最低 ${androidVersionName(info.minSdk)}'
                '・目標 ${androidVersionName(info.targetSdk)}'),
            _kv('檔案', '${info.fileName}・${formatBytes(info.fileSize)}'),
            if (inst?.signatureMatch == true)
              _kv('簽章', '與已安裝版本一致 ✓'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(k,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _warningsCard() {
    return Card(
      color: BrandColors.warning.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _warnings
              .map((w) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: BrandColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                            child:
                                Text(w, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  List<Widget> _splitSections(ArchiveInfo info) {
    final sections = <Widget>[];
    final groups = <SplitKind, String>{
      SplitKind.base: '主程式',
      SplitKind.abi: 'CPU 架構',
      SplitKind.dpi: '螢幕密度',
      SplitKind.lang: '語言',
      SplitKind.feature: '功能模組',
      SplitKind.other: '其他',
    };
    groups.forEach((kind, title) {
      final items = info.splits.where((s) => s.kind == kind).toList();
      if (items.isEmpty) return;
      sections.add(Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              ...items.map((s) => CheckboxListTile(
                    dense: true,
                    value: kind == SplitKind.base ? true : s.selected,
                    onChanged: kind == SplitKind.base
                        ? null
                        : (v) => setState(() => s.selected = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      '${s.tag.isNotEmpty ? '${s.tag}・' : ''}${formatBytes(s.size)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  )),
            ],
          ),
        ),
      ));
    });
    return sections;
  }

  Widget _obbCard(ArchiveInfo info) {
    final total = info.obbs.fold<int>(0, (a, b) => a + b.size);
    return Card(
      child: SwitchListTile(
        title: const Text('安裝 OBB 資源檔',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${info.obbs.length} 個檔案・${formatBytes(total)}，將複製到 Android/obb\n'
          '（新版 Android 可能限制寫入，失敗時僅安裝 APK）',
          style: const TextStyle(fontSize: 11.5),
        ),
        value: _installObb,
        onChanged: (v) => setState(() => _installObb = v),
      ),
    );
  }
}
