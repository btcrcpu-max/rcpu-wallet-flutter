import '../../core/biometric/biometric_auth.dart';
import '../../core/crypto/signature.dart';
import '../../core/models/address.dart';
import '../../core/network/native_rpc.dart';
import '../../core/qr/qr_scanner.dart';
import '../../core/utils/amount.dart';

/// 支付流程服务：解析扫码、金额校验、资产判定、指纹确认后签名广播。
///
/// 扫码协议：`rcpu:<address>?amount=<decimal>&asset=<native|wrcpu>&memo=<text>`
class PaymentService {
  final BiometricAuth biometric;
  final SignatureService signature;
  final NativeRpcClient nativeRpc;

  PaymentService({
    required this.biometric,
    required this.signature,
    required this.nativeRpc,
  });

  /// 解析扫码内容并校验金额合法性。
  static ScannedPayment parseAndValidate(String raw) {
    final payment = QrScanner.parse(raw);
    switch (payment.resolvedAsset) {
      case 'native':
        final addr = Address.parse(payment.address);
        if (!addr.isNative) {
          throw const FormatException('原生付款地址必须为 rcpu1 / rcpux1');
        }
      case 'wrcpu':
        final addr = Address.parse(payment.address);
        if (!addr.isEvm) {
          throw const FormatException('wRCPU 付款地址必须为 0x 开头');
        }
      default:
        throw const FormatException('不支持的资产类型');
    }
    if (payment.amount != null) {
      if (!Amount.isValid(payment.amount!)) {
        throw const FormatException('金额格式非法');
      }
      if (payment.amount == '0') {
        throw const FormatException('金额不能为 0');
      }
    }
    return payment;
  }

  /// 金额换算 micro 供交易构造。
  static int toMicro(String amount) => Amount.toMicro(amount);

  /// 指纹确认后发起支付（TC-SIG-03 核心路径）。
  ///
  /// 流程：指纹验证 → 构造交易 → 签名广播（签名占位时降级提示）。
  Future<PaymentResult> confirmAndPay({
    required String toAddress,
    required int amountMicro,
    required String privateKeyHex,
    required String assetType, // 'native' | 'wrcpu'
  }) async {
    // 1. 指纹验证
    final authOk = await biometric.authenticate(
      reason: '确认支付 ${amountMicro / 1e8} RCPU',
    );
    if (!authOk) {
      return PaymentResult.fail('指纹验证失败');
    }

    // 2. 构造交易（此处简化，实际需按地址类型构建）
    final txHex = _buildTxHex(toAddress, amountMicro);

    // 3. 签名并广播（含降级）
    try {
      final signed = await signature.signNative(txHex, privateKeyHex);
      final txid = await nativeRpc.broadcast(signed);
      return PaymentResult.ok(txid);
    } on UnimplementedError {
      // Path C 未落地时的降级
      if (toAddress.startsWith('rcpux1')) {
        return PaymentResult.fail('当前仅支持明文地址支付，隐私地址暂未开放');
      }
      // 明文地址可走其他已实现路径
      return PaymentResult.fail('原生签名暂未实现，请稍后重试');
    } catch (e) {
      return PaymentResult.fail('支付失败: $e');
    }
  }

  /// 构造交易 hex（原生交易构造逻辑落地前占位）。
  ///
  /// 返回可识别的占位字符串，便于日志排查，不影响降级流程。
  String _buildTxHex(String toAddress, int amountMicro) {
    return 'placeholder_tx_${toAddress}_${amountMicro}_${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// 支付结果：成功携带交易 ID；失败携带错误信息。
class PaymentResult {
  final bool ok;
  final String? txid;
  final String? error;

  const PaymentResult.ok(this.txid) : ok = true, error = null;
  const PaymentResult.fail(this.error) : ok = false, txid = null;
}