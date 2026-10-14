import 'dart:typed_data';

import '../../core/biometric/biometric_auth.dart';
import '../../core/crypto/bech32.dart';
import '../../core/crypto/bip341.dart';
import '../../core/crypto/native_tx.dart';
import '../../core/crypto/signature.dart';
import '../../core/models/address.dart';
import '../../core/models/native_utxo.dart';
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

  /// 默认费率（micro / vbyte）；可经 [confirmAndPay] 覆盖。
  static const int defaultFeeRateMicroPerByte = 1000;

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
  /// 流程：指纹验证 → 拉取 UTXO → 构造交易 → 签名广播。
  /// 隐私收款（`rcpux1`）本地无 CT 盲化能力 → `UnimplementedError` 降级提示；
  /// 明文收款（`rcpu1`）走完整 P2TR 输入 + P2WPKH 输出构造链。
  ///
  /// [fromAddress] 为自己地址（用于拉取 UTXO，须对应 [privateKeyHex]）；
  /// [changeAddress] 为找零地址（默认明文 [fromAddress]，须为 `rcpu1`）；
  /// [utxos] 仅供测试注入，缺省时经 [nativeRpc.getUtxos] 拉取。
  Future<PaymentResult> confirmAndPay({
    required String toAddress,
    required int amountMicro,
    required String privateKeyHex,
    required String assetType, // 'native' | 'wrcpu'
    String? fromAddress,
    String? changeAddress,
    List<NativeUtxo>? utxos,
    int feeRateMicroPerByte = defaultFeeRateMicroPerByte,
  }) async {
    // 1. 指纹验证
    final authOk = await biometric.authenticate(
      reason: '确认支付 ${amountMicro / 1e8} RCPU',
    );
    if (!authOk) {
      return const PaymentResult.fail('指纹验证失败');
    }

    // 2. 构造 + 签名 + 广播（含降级）
    try {
      final built = await _buildTxHex(
        toAddress: toAddress,
        amountMicro: amountMicro,
        fromAddress: fromAddress,
        changeAddress: changeAddress,
        utxos: utxos,
        feeRateMicroPerByte: feeRateMicroPerByte,
      );
      final signed = await signature.signNative(
        built.txHex,
        privateKeyHex,
        prevOuts: built.prevOuts,
      );
      final txid = await nativeRpc.broadcast(signed);
      return PaymentResult.ok(txid);
    } on UnimplementedError {
      // Path C 未落地时的降级（隐私收款需代理盲化回填）
      if (toAddress.startsWith('rcpux1')) {
        return const PaymentResult.fail('当前仅支持明文地址支付，隐私地址暂未开放');
      }
      return const PaymentResult.fail('原生签名暂未实现，请稍后重试');
    } catch (e) {
      return PaymentResult.fail('支付失败: $e');
    }
  }

  /// 构造原生明文收款交易（真实 UTXO 选择 + 输出构造 + fee）。
  ///
  /// - **输入**：仅选 [utxos] 中 P2TR（`0x51 0x20 || x-only`）、已确认的
  ///   可签名输出（BIP341 key-path 花费）；按需凑足「金额 + 手续费」，
  ///   避免暴露全部余额（最小足够集合）。
  /// - **收款输出**：明文 `rcpu1` → P2WPKH（`0x00 0x14 || h160`）。
  /// - **找零输出**：[changeAddress]（明文 P2WPKH）；差额归 fee。
  /// - **隐私收款**（`rcpux1`）：CT 盲化承诺需代理/官方库回填，本地
  ///   fail-closed 抛 [UnimplementedError]（path-c-spec §2.5，不静默降明文）。
  /// - [txHex] 为**未签名**交易；[prevOuts] 与输入一一对应，供
  ///   [SignatureService.signNative] 计算 BIP341 sighash。
  Future<BuiltNativeTx> _buildTxHex({
    required String toAddress,
    required int amountMicro,
    required String? fromAddress,
    String? changeAddress,
    List<NativeUtxo>? utxos,
    required int feeRateMicroPerByte,
  }) async {
    if (amountMicro <= 0) {
      throw const FormatException('金额必须为正');
    }
    final to = Address.parse(toAddress);
    if (to.isPrivate) {
      throw UnimplementedError('隐私收款需代理盲化回填 CT 输出');
    }
    if (!to.isPlain) {
      throw const FormatException('仅支持原生明文收款地址');
    }
    if (fromAddress == null || fromAddress.isEmpty) {
      throw const FormatException('缺少付款地址（fromAddress）');
    }
    final change = Address.parse(changeAddress ?? fromAddress);
    if (!change.isPlain) {
      throw const FormatException('找零地址须为明文 rcpu1（当前不支持 CT 找零）');
    }

    // 拉取 UTXO（测试可注入；生产走 get_utxos 代理）。
    final pool = (utxos ?? await nativeRpc.getUtxos(fromAddress))
        .where((u) => u.confirmed && u.isP2trInput)
        .toList()
      ..sort((a, b) => a.amountMicro.compareTo(b.amountMicro));
    if (pool.isEmpty) {
      throw StateError('没有可花费的 P2TR UTXO（余额不足或未同步）');
    }

    final toScript = _p2wpkhScript(to);
    final changeScript = _p2wpkhScript(change);

    // 1) UTXO 选择：最小足够集合（升序累加）。
    final selected = <NativeUtxo>[];
    var total = BigInt.zero;
    const assumedOutputs = 2; // 收款 + 找零（保守估值）
    for (final u in pool) {
      selected.add(u);
      total += BigInt.from(u.amountMicro);
      final fee = _estimateFee(selected.length, assumedOutputs, feeRateMicroPerByte);
      if (total >= BigInt.from(amountMicro) + BigInt.from(fee)) break;
    }
    var fee = _estimateFee(selected.length, assumedOutputs, feeRateMicroPerByte);
    if (total < BigInt.from(amountMicro) + BigInt.from(fee)) {
      throw StateError('余额不足：可用 ${Amount.fromMicro(total.toInt())} RCPU，'
          '需 ${Amount.fromMicro(amountMicro)} + 手续费');
    }

    // 2) 输出构造（找零差额归 fee；无找零时输出数收敛为 1）。
    var outputs = <NativeTxOut>[
      NativeTxOut(value: BigInt.from(amountMicro), scriptPubKey: toScript),
    ];
    var changeMicro = total - BigInt.from(amountMicro) - BigInt.from(fee);
    if (changeMicro > BigInt.zero) {
      outputs = [
        ...outputs,
        NativeTxOut(value: changeMicro, scriptPubKey: changeScript),
      ];
    } else {
      // 无找零：fee = total - amount（全部视为手续费，需为正）
      final actualFee = total - BigInt.from(amountMicro);
      if (actualFee < BigInt.zero) {
        throw StateError('余额不足（含手续费）');
      }
      fee = actualFee.toInt();
      changeMicro = BigInt.zero;
    }

    // 3) 交易体：version=2，sequence=0xfffffffd（RBF 可标记），locktime=0。
    final tx = NativeTx(
      version: 2,
      inputs: [
        for (final u in selected)
          NativeTxIn(
            prevTxid: u.prevTxid,
            prevVout: u.vout,
            scriptSig: Uint8List(0),
            sequence: 0xfffffffd,
          ),
      ],
      outputs: outputs,
      locktime: 0,
    );

    return BuiltNativeTx(
      txHex: NativeTxCodec.bytesToHex(tx.serialize()),
      prevOuts: [
        for (final u in selected)
          NativePrevOut(
            scriptPubKey: _hexBytes(u.scriptPubKey),
            amount: BigInt.from(u.amountMicro),
          ),
      ],
      feeMicro: fee,
      changeMicro: changeMicro.toInt(),
      inputCount: selected.length,
    );
  }

  /// 明文地址 → P2WPKH 锁定脚本（`0x00 0x14 || h160`，22 字节）。
  Uint8List _p2wpkhScript(Address addr) {
    // rcpu1 payload = 0x00 || hash160(20B)；取 hash160 段。
    final payload = Bech32.decodeToBytes(addr.value, isBech32m: false);
    if (payload.length != 21 || payload[0] != 0x00) {
      throw const FormatException('明文地址解码失败（payload 须为 0x00 || h160）');
    }
    return Uint8List.fromList([0x00, 0x14, ...payload.sublist(1, 21)]);
  }

  /// 估算交易 vsize 并乘费率：base + witness/4（P2TR 输入 66B witness，
  /// P2WPKH 输出 31B）。返回 micro 手续费。
  int _estimateFee(int nIn, int nOut, int feeRateMicroPerByte) {
    final base = 4 /*version*/ +
        1 /*vin varint*/ +
        nIn * (32 + 4 + 1 + 4) + // outpoint + scriptSigLen(1) + seq
        1 /*vout varint*/ +
        nOut * (8 + 1 + 22) + // value + scriptLen + P2WPKH(22)
        4 /*locktime*/;
    final witness = nIn * (1 + 1 + 64); // 元素数 + 长度 + Schnorr 64B
    final vsize = base + (witness + 3) ~/ 4;
    return vsize * feeRateMicroPerByte;
  }

  static Uint8List _hexBytes(String hex) {
    final h = hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();
    if (h.length.isOdd) throw const FormatException('hex 长度必须为偶数');
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}

/// 原生交易构造结果：未签名交易 hex + 签名所需 prevOuts。
class BuiltNativeTx {
  final String txHex;
  final List<NativePrevOut> prevOuts;
  final int feeMicro;
  final int changeMicro;
  final int inputCount;

  const BuiltNativeTx({
    required this.txHex,
    required this.prevOuts,
    required this.feeMicro,
    required this.changeMicro,
    required this.inputCount,
  });
}

/// 支付结果：成功携带交易 ID；失败携带错误信息。
class PaymentResult {
  final bool ok;
  final String? txid;
  final String? error;

  const PaymentResult.ok(this.txid) : ok = true, error = null;
  const PaymentResult.fail(this.error) : ok = false, txid = null;
}