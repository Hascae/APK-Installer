import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models.dart';

/// 原生事件。
class NativeEvent {
  final String type;
  final Map<dynamic, dynamic> data;
  NativeEvent(this.type, this.data);
}

/// 與原生安裝引擎溝通的唯一入口。
class InstallerChannel {
  InstallerChannel._();
  static final InstallerChannel instance = InstallerChannel._();

  static const _methods = MethodChannel('apkinstaller/methods');
  static const _events = EventChannel('apkinstaller/events');

  Stream<NativeEvent>? _eventStream;

  /// 廣播事件流（複製進度 / 安裝狀態 / 安裝結果 / 外部開檔）。
  Stream<NativeEvent> get events {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) {
          final m = e as Map<dynamic, dynamic>;
          return NativeEvent(m['type'] as String? ?? '', m);
        })
        .asBroadcastStream();
    return _eventStream!;
  }

  Future<DeviceInfo> getDeviceInfo() async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
    return DeviceInfo.fromMap(m!);
  }

  Future<PermissionState> getPermissionState() async {
    final m =
        await _methods.invokeMethod<Map<dynamic, dynamic>>('getPermissionState');
    return PermissionState.fromMap(m!);
  }

  Future<void> requestInstallPermission() =>
      _methods.invokeMethod('requestInstallPermission');

  Future<void> requestAllFilesPermission() =>
      _methods.invokeMethod('requestAllFilesPermission');

  /// 取得由檔案管理器 / 分享帶入的待處理檔案 URI。
  Future<String?> takePendingFile() =>
      _methods.invokeMethod<String>('takePendingFile');

  /// 將 content:// 匯入快取，回傳本機路徑。
  Future<({String path, String name, int size})> importUri(String uri) async {
    final m = await _methods
        .invokeMethod<Map<dynamic, dynamic>>('importUri', {'uri': uri});
    return (
      path: m!['path'] as String,
      name: m['name'] as String,
      size: (m['size'] as num).toInt(),
    );
  }

  Future<ArchiveInfo> analyze(String path) async {
    final m = await _methods
        .invokeMethod<Map<dynamic, dynamic>>('analyze', {'path': path});
    return ArchiveInfo.fromMap(m!);
  }

  /// 開始安裝，回傳 sessionId；結果經由 [events] 送達。
  Future<int> install({
    required String path,
    List<String>? entries,
    required String packageName,
    required String appLabel,
    bool allowUserActionSkip = false,
    bool requestUpdateOwnership = false,
  }) async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('install', {
      'path': path,
      'entries': entries,
      'packageName': packageName,
      'appLabel': appLabel,
      'allowUserActionSkip': allowUserActionSkip,
      'requestUpdateOwnership': requestUpdateOwnership,
    });
    return (m!['sessionId'] as num).toInt();
  }

  Future<({bool ok, String message})> installObb({
    required String path,
    required List<String> entries,
    required String packageName,
  }) async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('installObb', {
      'path': path,
      'entries': entries,
      'packageName': packageName,
    });
    return (ok: m!['ok'] as bool? ?? false, message: m['message'] as String? ?? '');
  }

  Future<void> uninstall(String packageName, String appLabel) =>
      _methods.invokeMethod('uninstall', {
        'packageName': packageName,
        'appLabel': appLabel,
      });

  Future<List<InstalledApp>> listApps({bool includeSystem = false}) async {
    final list = await _methods
        .invokeMethod<List<dynamic>>('listApps', {'includeSystem': includeSystem});
    return list!.map((e) => InstalledApp.fromMap(e as Map)).toList();
  }

  Future<Uint8List?> getAppIcon(String packageName, {int sizePx = 96}) =>
      _methods.invokeMethod<Uint8List>('getAppIcon', {
        'packageName': packageName,
        'sizePx': sizePx,
      });

  Future<({String path, String name, int size})> exportApp(
      String packageName) async {
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'exportApp', {'packageName': packageName});
    return (
      path: m!['path'] as String,
      name: m['name'] as String,
      size: (m['size'] as num).toInt(),
    );
  }

  Future<bool> openApp(String packageName) async =>
      await _methods.invokeMethod<bool>('openApp', {'packageName': packageName}) ??
      false;

  Future<void> openAppSettings(String packageName) =>
      _methods.invokeMethod('openAppSettings', {'packageName': packageName});

  Future<int> clearCache() async =>
      (await _methods.invokeMethod<num>('clearCache'))?.toInt() ?? 0;
}
