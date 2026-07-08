import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/brand.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}（${info.buildNumber}）');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('關於')),
      body: ListView(
        // 底部加上系統導覽列安全區
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          const SizedBox(height: 16),
          const Center(child: BrandLogo(size: 96)),
          const SizedBox(height: 16),
          Center(
            child: Text('安裝大師',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                )),
          ),
          if (_version.isNotEmpty)
            Center(
              child: Text('版本 $_version',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withOpacity(0.5),
                  )),
            ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('功能特色',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10),
                  _Feature('支援 APK、APKM、XAPK、APKS 與含分割包的 ZIP'),
                  _Feature('自動依裝置架構、螢幕密度與語言挑選分割包'),
                  _Feature('XAPK 的 OBB 資源檔自動複製'),
                  _Feature('多檔批次安裝佇列'),
                  _Feature('降級與簽章衝突事前偵測'),
                  _Feature('已安裝應用匯出為 APK / APKS'),
                  _Feature('完整支援 Android 7 ～ Android 16'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '本應用僅供安裝您擁有合法使用權的應用程式。'
                '安裝來源不明的應用程式可能危害裝置安全，請謹慎確認來源。',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_rounded,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
