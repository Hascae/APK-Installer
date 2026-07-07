import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 應用標誌（與啟動圖示同款的「下載入匣」符號），以 CustomPainter 繪製，
/// 任意尺寸皆清晰 —— 自製美術資源，不依賴系統圖示。
class BrandLogo extends StatelessWidget {
  final double size;
  final bool withBackground;

  const BrandLogo({super.key, this.size = 64, this.withBackground = true});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(withBackground: withBackground),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool withBackground;
  _LogoPainter({required this.withBackground});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (withBackground) {
      final bgPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2150), Color(0xFF0C0F26)],
        ).createShader(Rect.fromLTWH(0, 0, s, s));
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * 0.24),
      );
      canvas.drawRRect(rrect, bgPaint);
    }

    final glyphPaint = Paint()
      ..shader = BrandColors.glyphGradient
          .createShader(Rect.fromLTWH(0, s * 0.1, s, s * 0.8));

    final u = s / 1024.0;
    final scale = withBackground ? 0.72 : 0.94;
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(scale);
    canvas.translate(-s / 2, -s / 2);

    // 箭頭桿
    final shaftW = 150 * u;
    final shaft = RRect.fromRectAndRadius(
      Rect.fromLTRB(s / 2 - shaftW / 2, 150 * u, s / 2 + shaftW / 2, 520 * u),
      Radius.circular(shaftW / 2),
    );
    canvas.drawRRect(shaft, glyphPaint);

    // 箭頭頭
    final head = Path()
      ..moveTo(s / 2 - 210 * u, 480 * u)
      ..lineTo(s / 2 + 210 * u, 480 * u)
      ..lineTo(s / 2, 690 * u)
      ..close();
    canvas.drawPath(head, glyphPaint);

    // 收納匣（開口向上）
    final stroke = 95 * u;
    final trayPaint = Paint()
      ..shader = glyphPaint.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final left = 200 * u + stroke / 2;
    final right = 824 * u - stroke / 2;
    final top = 610 * u;
    final bottom = 880 * u - stroke / 2;
    final rad = 110 * u;
    final tray = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom - rad)
      ..arcTo(Rect.fromLTWH(left, bottom - rad * 2, rad * 2, rad * 2),
          math.pi, -math.pi / 2, false)
      ..lineTo(right - rad, bottom)
      ..arcTo(Rect.fromLTWH(right - rad * 2, bottom - rad * 2, rad * 2, rad * 2),
          math.pi / 2, -math.pi / 2, false)
      ..lineTo(right, top);
    canvas.drawPath(tray, trayPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.withBackground != withBackground;
}

/// 應用圖示縮圖（PNG bytes → 圓角圖片；無資料時顯示自製預設圖）。
class AppIconImage extends StatelessWidget {
  final Uint8List? bytes;
  final double size;

  const AppIconImage({super.key, required this.bytes, this.size = 48});

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return BrandLogo(size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.memory(
        bytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

/// 檔案類型徽章（APK / APKM / XAPK / APKS）。
class FileTypeBadge extends StatelessWidget {
  final String fileName;

  const FileTypeBadge({super.key, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'APK';
    final color = switch (ext) {
      'APK' => BrandColors.cyan,
      'APKM' => BrandColors.indigo,
      'XAPK' => BrandColors.warning,
      'APKS' => BrandColors.success,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        ext,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

/// 空狀態插畫：向下箭頭 + 虛線收納匣，自製繪圖。
class EmptyState extends StatelessWidget {
  final String message;

  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.45,
            child: BrandLogo(size: 88, withBackground: false),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}
