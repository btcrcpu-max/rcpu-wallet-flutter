import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Address;

import '../../core/l10n/app_strings.dart';
import '../../core/models/address.dart';
import '../../core/qr/qr_scanner.dart';

/// 扫码页：识别 `rcpu:` 收款 URI 或裸地址二维码。
///
/// 防注入（与 [QrScanner.acceptCode] 同一策略）：仅接受能解析为
/// `rcpu:` 协议的内容，或能通过 [Address.parse] 识别的地址文本；
/// 其余内容（网页 URL、任意文本）一律拒绝，返回 null 由调用方处理。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;
  String? _lastRejected;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final text = raw.trim();
    final valid = QrScanner.acceptCode(text) || _isAddress(text);
    if (!valid) {
      // 同一无效内容只提示一次，避免连扫时 SnackBar 刷屏。
      if (_lastRejected != text) {
        _lastRejected = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.current.qrUnrecognized)),
        );
      }
      return;
    }
    _done = true;
    Navigator.of(context).pop(text);
  }

  bool _isAddress(String raw) {
    try {
      Address.parse(raw);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.current;
    return Scaffold(
      appBar: AppBar(title: Text(s.scanTitle)),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              // 展示真实错误码，便于区分权限拒绝 / 相机被占用 /
              // ML Kit 初始化失败等不同根因（统一文案会误导排查）。
              final detail = StringBuffer()
                ..write('${s.errorCodeLabel}: ${error.errorCode}')
                ..write('\n${error.errorDetails?.message ?? ''}');
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_camera_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(s.cameraStartFailed,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        detail.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.cameraPermissionHint,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(s.back),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s.scanHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
