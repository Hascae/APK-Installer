import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// 安裝 / 解除安裝歷史（本機保存，最多 200 筆）。
class HistoryStore {
  HistoryStore._();
  static final HistoryStore instance = HistoryStore._();

  static const _key = 'install_history_v1';
  static const _maxEntries = 200;

  Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(HistoryEntry entry) async {
    final list = await load();
    list.insert(0, entry);
    while (list.length > _maxEntries) {
      list.removeLast();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
