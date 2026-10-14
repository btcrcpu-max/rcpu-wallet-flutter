import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码结果：解析后的付款目标。
class ScannedPayment {
  final String address;

  /// 金额（十进制字符串，可空）
  final String? amount;

  /// 资产类型（native / wrcpu，可空，缺省按地址前缀推断）
  final String? asset;

  /// 备注（可空）
  final String? memo;

  const ScannedPayment({
    required this.address,
    this.amount,
    this.asset,
    this.memo,
  });

  /// 是否原生地址（rcpu1 / rcpux1 前缀）。
  bool get isNative => address.startsWith('rcpu1') || address.startsWith('rcpux1');

  /// 是否 wRCPU（0x 前缀）。
  bool get isWrcpu => address.startsWith('0x');

  String get resolvedAsset {
    if (asset != null && asset!.isNotEmpty) return asset!;
    return isNative ? 'native' : 'wrcpu';
  }
}

/// 二维码扫描封装（mobile_scanner）。
///
/// 识别 `rcpu:` 前缀后解析地址、金额与资产；其余内容一律拒绝，
/// 防止扫码误触网页或恶意 URI。
class QrScanner {
  /// 解析扫码文本为付款目标；非 rcpu: 协议抛 [FormatException]。
  static ScannedPayment parse(String raw) {
    final text = raw.trim();
    if (!text.startsWith('rcpu:')) {
      throw const FormatException('非 rcpu: 协议，已拒绝');
    }
    final body = text.substring(5);
    final queryIndex = body.indexOf('?');
    final address = queryIndex < 0 ? body : body.substring(0, queryIndex);
    if (address.isEmpty) {
      throw const FormatException('缺少收款地址');
    }
    String? amount;
    String? asset;
    String? memo;
    if (queryIndex >= 0) {
      final query = body.substring(queryIndex + 1);
      for (final pair in query.split('&')) {
        final kv = pair.split('=');
        if (kv.length != 2) continue;
        switch (kv[0]) {
          case 'amount':
            amount = Uri.decodeComponent(kv[1]);
          case 'asset':
            asset = Uri.decodeComponent(kv[1]);
          case 'memo':
            memo = Uri.decodeComponent(kv[1]);
        }
      }
    }
    return ScannedPayment(address: address, amount: amount, asset: asset, memo: memo);
  }

  /// 平台回调防注入：只接受 rcpu: 内容。
  static bool acceptCode(String? value) {
    if (value == null) return false;
    try {
      parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 扫描控制器（mobile_scanner 控制器）。
class ScannerController {
  final MobileScannerController controller = MobileScannerController();

  Future<void> start() => controller.start();
  Future<void> stop() => controller.stop();
  Future<void> dispose() => controller.dispose();
}