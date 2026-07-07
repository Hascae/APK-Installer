import 'package:flutter/material.dart';

import '../models.dart';
import '../services/history_store.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// 安裝 / 解除安裝歷史。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await HistoryStore.instance.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除歷史'),
        content: const Text('確定要清除所有安裝歷史紀錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BrandColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await HistoryStore.instance.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('安裝歷史'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: '清除歷史',
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const EmptyState(message: '還沒有任何安裝紀錄\n完成第一次安裝後會顯示在這裡')
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = _entries[i];
                    return ListTile(
                      leading: Icon(
                        h.success
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        color: h.success
                            ? BrandColors.success
                            : BrandColors.danger,
                      ),
                      title: Text(
                        '${h.label}${h.versionName.isNotEmpty ? '（${h.versionName}）' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${h.kind == 'uninstall' ? '解除安裝' : '安裝'}'
                        '${h.success ? '成功' : '失敗'}・${formatTime(h.time)}'
                        '${h.message.isNotEmpty ? '\n${h.message}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      isThreeLine: h.message.isNotEmpty,
                    );
                  },
                ),
    );
  }
}
