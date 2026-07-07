import 'dart:typed_data';

/// 分割 APK 分類。
enum SplitKind { base, abi, dpi, lang, feature, other }

SplitKind splitKindFrom(String s) {
  switch (s) {
    case 'base':
      return SplitKind.base;
    case 'abi':
      return SplitKind.abi;
    case 'dpi':
      return SplitKind.dpi;
    case 'lang':
      return SplitKind.lang;
    case 'feature':
      return SplitKind.feature;
    default:
      return SplitKind.other;
  }
}

class SplitItem {
  final String entry;
  final String name;
  final int size;
  final SplitKind kind;
  final String tag;
  bool selected;

  SplitItem({
    required this.entry,
    required this.name,
    required this.size,
    required this.kind,
    required this.tag,
    this.selected = false,
  });

  factory SplitItem.fromMap(Map<dynamic, dynamic> m) => SplitItem(
        entry: m['entry'] as String,
        name: m['name'] as String,
        size: (m['size'] as num?)?.toInt() ?? 0,
        kind: splitKindFrom(m['kind'] as String? ?? 'other'),
        tag: m['tag'] as String? ?? '',
      );
}

class ObbItem {
  final String entry;
  final String name;
  final int size;

  ObbItem({required this.entry, required this.name, required this.size});

  factory ObbItem.fromMap(Map<dynamic, dynamic> m) => ObbItem(
        entry: m['entry'] as String,
        name: m['name'] as String,
        size: (m['size'] as num?)?.toInt() ?? 0,
      );
}

class InstalledInfo {
  final String versionName;
  final int versionCode;
  final bool? signatureMatch;
  final bool isSelf;

  InstalledInfo({
    required this.versionName,
    required this.versionCode,
    required this.signatureMatch,
    required this.isSelf,
  });

  factory InstalledInfo.fromMap(Map<dynamic, dynamic> m) => InstalledInfo(
        versionName: m['versionName'] as String? ?? '',
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        signatureMatch: m['signatureMatch'] as bool?,
        isSelf: m['isSelf'] as bool? ?? false,
      );
}

/// 安裝包完整解析結果。
class ArchiveInfo {
  final String kind; // apk | bundle
  final String path;
  final String fileName;
  final int fileSize;
  final String packageName;
  final String label;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;
  final Uint8List? iconBytes;
  final InstalledInfo? installed;
  final List<SplitItem> splits;
  final List<ObbItem> obbs;
  final String? baseEntry;

  ArchiveInfo({
    required this.kind,
    required this.path,
    required this.fileName,
    required this.fileSize,
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.iconBytes,
    required this.installed,
    required this.splits,
    required this.obbs,
    required this.baseEntry,
  });

  bool get isBundle => kind == 'bundle';

  factory ArchiveInfo.fromMap(Map<dynamic, dynamic> m) => ArchiveInfo(
        kind: m['kind'] as String? ?? 'apk',
        path: m['path'] as String,
        fileName: m['fileName'] as String? ?? '',
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        packageName: m['packageName'] as String? ?? '',
        label: m['label'] as String? ?? '',
        versionName: m['versionName'] as String? ?? '',
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        minSdk: (m['minSdk'] as num?)?.toInt() ?? 0,
        targetSdk: (m['targetSdk'] as num?)?.toInt() ?? 0,
        iconBytes: m['iconBytes'] as Uint8List?,
        installed: m['installed'] == null
            ? null
            : InstalledInfo.fromMap(m['installed'] as Map),
        splits: ((m['splits'] as List?) ?? const [])
            .map((e) => SplitItem.fromMap(e as Map))
            .toList(),
        obbs: ((m['obbs'] as List?) ?? const [])
            .map((e) => ObbItem.fromMap(e as Map))
            .toList(),
        baseEntry: m['baseEntry'] as String?,
      );
}

class DeviceInfo {
  final int sdkInt;
  final String release;
  final String model;
  final String brand;
  final List<String> abis;
  final int densityDpi;
  final List<String> locales;

  DeviceInfo({
    required this.sdkInt,
    required this.release,
    required this.model,
    required this.brand,
    required this.abis,
    required this.densityDpi,
    required this.locales,
  });

  factory DeviceInfo.fromMap(Map<dynamic, dynamic> m) => DeviceInfo(
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
        release: m['release'] as String? ?? '',
        model: m['model'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        abis: ((m['abis'] as List?) ?? const []).cast<String>(),
        densityDpi: (m['densityDpi'] as num?)?.toInt() ?? 480,
        locales: ((m['locales'] as List?) ?? const []).cast<String>(),
      );
}

class PermissionState {
  final bool canInstall;
  final bool allFiles;
  final bool legacyStorage;
  final bool notifications;
  final int sdkInt;

  PermissionState({
    required this.canInstall,
    required this.allFiles,
    required this.legacyStorage,
    required this.notifications,
    required this.sdkInt,
  });

  factory PermissionState.fromMap(Map<dynamic, dynamic> m) => PermissionState(
        canInstall: m['canInstall'] as bool? ?? false,
        allFiles: m['allFiles'] as bool? ?? false,
        legacyStorage: m['legacyStorage'] as bool? ?? false,
        notifications: m['notifications'] as bool? ?? false,
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
      );
}

class InstalledApp {
  final String package;
  final String label;
  final String versionName;
  final int versionCode;
  final bool system;
  final int splits;
  final int apkSize;
  final int firstInstall;
  final int lastUpdate;
  final bool enabled;

  InstalledApp({
    required this.package,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.system,
    required this.splits,
    required this.apkSize,
    required this.firstInstall,
    required this.lastUpdate,
    required this.enabled,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> m) => InstalledApp(
        package: m['package'] as String,
        label: m['label'] as String? ?? '',
        versionName: m['versionName'] as String? ?? '',
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        system: m['system'] as bool? ?? false,
        splits: (m['splits'] as num?)?.toInt() ?? 0,
        apkSize: (m['apkSize'] as num?)?.toInt() ?? 0,
        firstInstall: (m['firstInstall'] as num?)?.toInt() ?? 0,
        lastUpdate: (m['lastUpdate'] as num?)?.toInt() ?? 0,
        enabled: m['enabled'] as bool? ?? true,
      );
}

/// 安裝歷史紀錄。
class HistoryEntry {
  final int time; // epoch ms
  final String package;
  final String label;
  final String versionName;
  final String kind; // install | uninstall
  final bool success;
  final String message;

  HistoryEntry({
    required this.time,
    required this.package,
    required this.label,
    required this.versionName,
    required this.kind,
    required this.success,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'package': package,
        'label': label,
        'versionName': versionName,
        'kind': kind,
        'success': success,
        'message': message,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> m) => HistoryEntry(
        time: (m['time'] as num?)?.toInt() ?? 0,
        package: m['package'] as String? ?? '',
        label: m['label'] as String? ?? '',
        versionName: m['versionName'] as String? ?? '',
        kind: m['kind'] as String? ?? 'install',
        success: m['success'] as bool? ?? false,
        message: m['message'] as String? ?? '',
      );
}

/// 檔案大小格式化。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  double v = bytes.toDouble();
  int i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// 時間格式化（yyyy/MM/dd HH:mm）。
String formatTime(int epochMs) {
  if (epochMs <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Android API 級別對應的版本名稱（7 ～ 16）。
String androidVersionName(int sdk) {
  const names = {
    24: 'Android 7.0',
    25: 'Android 7.1',
    26: 'Android 8.0',
    27: 'Android 8.1',
    28: 'Android 9',
    29: 'Android 10',
    30: 'Android 11',
    31: 'Android 12',
    32: 'Android 12L',
    33: 'Android 13',
    34: 'Android 14',
    35: 'Android 15',
    36: 'Android 16',
  };
  if (names.containsKey(sdk)) return '${names[sdk]}（API $sdk）';
  if (sdk > 36) return 'Android 16+（API $sdk）';
  if (sdk <= 0) return '未知';
  return 'API $sdk';
}
