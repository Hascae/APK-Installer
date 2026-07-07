import '../models.dart';

/// 依裝置條件（ABI / 螢幕密度 / 語言）自動挑選分割包，
/// 對標並超越 APKMirror Installer 的自動選擇邏輯。
class SplitSelector {
  static const _dpiBuckets = <String, int>{
    'ldpi': 120,
    'mdpi': 160,
    'tvdpi': 213,
    'hdpi': 240,
    'xhdpi': 320,
    'xxhdpi': 480,
    'xxxhdpi': 640,
  };

  /// 就地更新 [splits] 的 selected 欄位，回傳警告訊息清單。
  static List<String> autoSelect(List<SplitItem> splits, DeviceInfo device) {
    final warnings = <String>[];
    if (splits.isEmpty) return warnings;

    for (final s in splits) {
      s.selected = false;
    }

    // 1. base 一律必選
    for (final s in splits.where((s) => s.kind == SplitKind.base)) {
      s.selected = true;
    }

    // 2. ABI：依裝置支援順序挑第一個有對應分割的架構
    final abiSplits = splits.where((s) => s.kind == SplitKind.abi).toList();
    if (abiSplits.isNotEmpty) {
      String norm(String abi) => abi.toLowerCase().replaceAll('-', '_');
      final available = abiSplits.map((s) => norm(s.tag)).toSet();
      String? chosen;
      for (final abi in device.abis) {
        if (available.contains(norm(abi))) {
          chosen = norm(abi);
          break;
        }
      }
      if (chosen != null) {
        for (final s in abiSplits) {
          s.selected = norm(s.tag) == chosen;
        }
      } else {
        warnings.add('找不到符合此裝置 CPU 架構（${device.abis.join('、')}）的分割包，'
            '安裝後應用可能無法運作');
      }
    }

    // 3. 螢幕密度：挑最接近（優先不低於裝置密度）的一個
    final dpiSplits = splits.where((s) => s.kind == SplitKind.dpi).toList();
    if (dpiSplits.isNotEmpty) {
      SplitItem? best;
      int bestScore = 1 << 30;
      for (final s in dpiSplits) {
        final dpi = _dpiBuckets[s.tag.toLowerCase()];
        if (dpi == null) continue;
        // 不低於裝置密度者差值直接比較；低於者加重罰分
        final diff = dpi - device.densityDpi;
        final score = diff >= 0 ? diff : -diff * 2 + 1000;
        if (score < bestScore) {
          bestScore = score;
          best = s;
        }
      }
      // nodpi 或無法辨識時全不選也沒關係（base 內含預設資源）
      best?.selected = true;
      for (final s in dpiSplits.where((s) => s.tag.toLowerCase() == 'nodpi')) {
        s.selected = true;
      }
    }

    // 4. 語言：符合裝置語言者全選；一律附選 zh 系列（本應用使用者以中文為主）
    final langSplits = splits.where((s) => s.kind == SplitKind.lang).toList();
    if (langSplits.isNotEmpty) {
      final deviceLangs = device.locales
          .map((l) => l.split('-').first.toLowerCase())
          .toSet();
      bool any = false;
      for (final s in langSplits) {
        final lang = s.tag.split('_').first.toLowerCase();
        if (deviceLangs.contains(lang) || lang == 'zh') {
          s.selected = true;
          any = true;
        }
      }
      // 完全沒有符合語言時，選 en 作為後備（多數應用的預設語言）
      if (!any) {
        for (final s in langSplits
            .where((s) => s.tag.split('_').first.toLowerCase() == 'en')) {
          s.selected = true;
        }
      }
    }

    // 5. 動態功能模組與其他：預設全選（缺少必要模組會導致安裝失敗）
    for (final s in splits.where(
        (s) => s.kind == SplitKind.feature || s.kind == SplitKind.other)) {
      s.selected = true;
    }

    return warnings;
  }
}
