import 'package:flutter_test/flutter_test.dart';
import 'package:rcpu_wallet/core/qr/qr_generator.dart';
import 'package:rcpu_wallet/core/qr/qr_scanner.dart';
import 'package:rcpu_wallet/features/payment/payment_service.dart';

/// 二维码与支付解析测试组（对应 docs/ct-test-cases.md 第 3、4 节）。
///
/// 覆盖：
/// - TC-CT-IN-03 收款二维码（rcpu: URI 生成）
/// - TC-CT-OUT-01 扫码解析与资产预判（rcpux1 隐私 / rcpu1 明文 / 0x wRCPU）
/// - TC-CT-OUT-04 金额校验分支（金额为 0 拒绝，不产生签名对象）
void main() {
  group('TC-CT-IN-03 收款二维码生成', () {
    test('rcpux1 隐私收款码：rcpu:rcpux1...?amount=1.5', () {
      final uri = QrGenerator.buildRcpuUri(
        address: 'rcpux1test',
        amount: '1.5',
      );
      expect(uri, 'rcpu:rcpux1test?amount=1.5');
    });

    test('rcpu1 明文收款码：可省略金额', () {
      final uri = QrGenerator.buildRcpuUri(address: 'rcpu1test');
      expect(uri, 'rcpu:rcpu1test');
    });

    test('带 memo 时按 URL 编码', () {
      final uri = QrGenerator.buildRcpuUri(
        address: 'rcpu1test',
        amount: '0.8',
        memo: '午餐 AA',
      );
      expect(uri, 'rcpu:rcpu1test?amount=0.8&memo=%E5%8D%88%E9%A4%90%20AA');
    });
  });

  group('TC-CT-OUT-01 扫码解析与资产预判', () {
    test('rcpux1 地址预判为隐私 native 付款，金额 1.5', () {
      final p = PaymentService.parseAndValidate('rcpu:rcpux1x?amount=1.5');
      expect(p.address, 'rcpux1x');
      expect(p.amount, '1.5');
      expect(p.resolvedAsset, 'native');
    });

    test('rcpu1 地址预判为明文 native 付款，金额 0.8', () {
      final p = PaymentService.parseAndValidate('rcpu:rcpu1y?amount=0.8');
      expect(p.address, 'rcpu1y');
      expect(p.amount, '0.8');
      expect(p.resolvedAsset, 'native');
    });

    test('0x 地址预判为 wRCPU（BSC）', () {
      final p = PaymentService.parseAndValidate(
          'rcpu:0x0000000000000000000000000000000000000001?amount=2');
      expect(p.resolvedAsset, 'wrcpu');
    });

    test('原生地址显式 asset=native 通过校验', () {
      expect(
        () => PaymentService.parseAndValidate('rcpu:rcpu1z?amount=1&asset=native'),
        returnsNormally,
      );
    });

    test('wrcpu 付款地址必须 0x 开头', () {
      expect(
        () => PaymentService.parseAndValidate('rcpu:rcpu1z?amount=1&asset=wrcpu'),
        throwsFormatException,
      );
    });

    test('非 rcpu: 协议一律拒绝（防误触网页）', () {
      expect(() => QrScanner.parse('https://evil.com'), throwsFormatException);
      expect(QrScanner.acceptCode('https://evil.com'), isFalse);
      expect(QrScanner.acceptCode(null), isFalse);
    });
  });

  group('TC-CT-OUT-04 金额校验（拒绝非法金额，不进入签名流程）', () {
    test('金额为 0 拒绝', () {
      expect(
        () => PaymentService.parseAndValidate('rcpu:rcpu1z?amount=0'),
        throwsFormatException,
      );
    });

    test('金额格式非法（负数）拒绝', () {
      expect(
        () => PaymentService.parseAndValidate('rcpu:rcpu1z?amount=-1'),
        throwsFormatException,
      );
    });

    test('金额精度超 8 位拒绝', () {
      expect(
        () => PaymentService.parseAndValidate('rcpu:rcpu1z?amount=0.123456789'),
        throwsFormatException,
      );
    });

    test('正确金额可换算为 micro 整数', () {
      expect(PaymentService.toMicro('1.5'), 150000000);
    });
  });
}