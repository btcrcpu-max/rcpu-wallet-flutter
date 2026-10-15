import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Address;

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
          const SnackBar(content: Text('无法识别的二维码内容，已忽略')),
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
    return Scaffold(
      appBar: AppBar(title: const Text('扫描收款码')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) {
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
                      const Text('相机不可用',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text(
                        '请检查系统权限：设置 → 应用 → rcpu_wallet → 权限 → 相机，'
                        '选择「允许」后返回重试。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回'),
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
              child: const Text(
                '对准收款方二维码（支持 rcpu: 收款码或地址二维码）',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
