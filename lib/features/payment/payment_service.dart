import 'dart:typed_data';

import '../../core/biometric/biometric_auth.dart';
import '../../core/crypto/bech32.dart';
import '../../core/crypto/derivation.dart';
import '../../core/crypto/native_tx.dart';
import '../../core/crypto/signature.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/address.dart';
import '../../core/models/native_utxo.dart';
import '../../core/network/ct_helper_client.dart';
import '../../core/network/native_rpc.dart';
import '../../core/qr/qr_scanner.dart';
import '../../core/utils/amount.dart';
import '../../core/utils/ct_resolver.dart';

/// 支付流程服务：解析扫码、金额校验、资产判定、指纹确认后签名广播。
///
/// 扫码协议：`rcpu:<address>?amount=<decimal>&asset=<native|wrcpu>&memo=<text>`
///
/// 原生链两条通路：
/// - **明文收款**（`rcpu1`，P2WPKH）：本地构造 + BIP143/ECDSA 或 BIP341 签名；
/// - **隐私收款**（`rcpux1`，CT）：输出盲化（Pedersen 承诺 + range proof）由
///   服务器 CT 协处理器（[CtHelperClient]）完成，私钥留在设备内签名。App 侧
///   仅在本地做 ECDH/HKDF 推导 rewind nonce 与拼装 witness。
class PaymentService {
  final BiometricAuth biometric;
  final SignatureService signature;
  final NativeRpcClient nativeRpc;

  /// CT 盲化协处理器客户端；为空表示未启用隐私（CT）支付。
  final CtHelperClient? ctHelper;

  /// 默认费率（micro / vbyte）；可经 [confirmAndPay] 覆盖。
  static const int defaultFeeRateMicroPerByte = 1000;

  PaymentService({
    required this.biometric,
    required this.signature,
    required this.nativeRpc,
    this.ctHelper,
  });

  /// 解析扫码内容并校验金额合法性。
  static ScannedPayment parseAndValidate(String raw) {
    final payment = QrScanner.parse(raw);
    switch (payment.resolvedAsset) {
      case 'native':
        final addr = Address.parse(payment.address);
        if (!addr.isNative) {
          throw FormatException(AppStrings.current.nativePayAddrPrefix);
        }
      case 'wrcpu':
        final addr = Address.parse(payment.address);
        if (!addr.isEvm) {
          throw FormatException(AppStrings.current.wrcpuPayAddrPrefix);
        }
      default:
        throw FormatException(AppStrings.current.unsupportedAsset);
    }
    if (payment.amount != null) {
      if (!Amount.isValid(payment.amount!)) {
        throw FormatException(AppStrings.current.amountInvalid);
      }
      if (payment.amount == '0') {
        throw FormatException(AppStrings.current.amountZero);
      }
    }
    return payment;
  }

  /// 金额换算 micro 供交易构造。
  static int toMicro(String amount) => Amount.toMicro(amount);

  /// 指纹确认后发起支付（TC-SIG-03 核心路径）。
  ///
  /// 流程：指纹验证 → 拉取 UTXO → 构造交易 → 签名广播。
  /// - 明文收款（`rcpu1`）走本地 P2WPKH/P2TR 输入 + P2WPKH 输出构造链；
  /// - 隐私收款（`rcpux1`）走 CT 通路（输出盲化经 [ctHelper]，输入若含 CT
  ///   输出则先本地 unblind）；
  /// - 未配置 [ctHelper] 时隐私收款 fail-closed（不静默降明文）。
  ///
  /// [fromAddress] 为自己明文地址（用于拉取明文 UTXO，须对应 [privateKeyHex]）；
  /// [privateKeyHex] 为明文路径私钥（`m/84'/1'/0'/0/0`）；
  /// [ctPrivateKeyHex] / [privateAddress] 为自己的隐私路径私钥与 `rcpux1`
  /// 地址（CT 找零与 CT 输入解盲/签名使用，`m/84'/1'/0'/1/0`）；
  /// [utxos] / [ctUtxos] 仅供测试注入；
  /// [subtractFeeFromAmount] 为「最大付款」模式：花费全部可用输入（明文
  /// 收款路径为全部明文 UTXO；隐私收款路径为明文 + CT 全部输入），手续费
  /// 从付款金额中扣除（无找零），交易内实付金额按实际尺寸校正后重算。
  Future<PaymentResult> confirmAndPay({
    required String toAddress,
    required int amountMicro,
    required String privateKeyHex,
    required String assetType, // 'native' | 'wrcpu'
    String? fromAddress,
    String? changeAddress,
    List<NativeUtxo>? utxos,
    int feeRateMicroPerByte = defaultFeeRateMicroPerByte,
    String? ctPrivateKeyHex,
    String? privateAddress,
    List<NativeUtxo>? ctUtxos,
    bool subtractFeeFromAmount = false,
  }) async {
    // 1. 指纹验证
    final authOk = await biometric.authenticate(
      reason: AppStrings.current.payConfirmReason('${amountMicro / 1e8}'),
    );
    if (!authOk) {
      return PaymentResult.fail(AppStrings.current.fingerprintFailed);
    }

    // 2. 构造 + 签名 + 广播（含降级）
    try {
      final String signed;
      final to = Address.parse(toAddress);
      if (assetType == 'native' && !to.isPrivate) {
        // 纯机密模式：原生资产不再受理明文目标地址（明文 UTXO 仍可作为
        // CT 输入被消费，实现自动转换）。
        return PaymentResult.fail(AppStrings.current.ctOnlyAddr);
      }
      if (assetType == 'native' && to.isPrivate) {
        signed = await _signCtPayment(
          to: to,
          amountMicro: amountMicro,
          plainKeyHex: privateKeyHex,
          ctKeyHex: ctPrivateKeyHex,
          privateAddress: privateAddress,
          plainAddress: fromAddress,
          utxos: utxos,
          ctUtxos: ctUtxos,
          feeRateMicroPerByte: feeRateMicroPerByte,
          subtractFee: subtractFeeFromAmount,
        );
      } else {
        final built = await buildNativeTxHex(
          toAddress: toAddress,
          amountMicro: amountMicro,
          fromAddress: fromAddress,
          changeAddress: changeAddress,
          utxos: utxos,
          feeRateMicroPerByte: feeRateMicroPerByte,
          subtractFee: subtractFeeFromAmount,
        );
        signed = await signature.signNative(
          built.txHex,
          privateKeyHex,
          prevOuts: built.prevOuts,
        );
      }
      final txid = await nativeRpc.broadcast(signed);
      return PaymentResult.ok(txid);
    } on UnimplementedError {
      if (toAddress.startsWith('rcpux1')) {
        return PaymentResult.fail(AppStrings.current.ctProxyMissing);
      }
      return PaymentResult.fail(AppStrings.current.nativeSignNotReady);
    } catch (e) {
      return PaymentResult.fail(AppStrings.current.paymentFailed('$e'));
    }
  }

  /// ================================================================ //
  /// 机密交易（CT）支付通路
  /// ================================================================ //

  /// 隐私收款构造 + 签名，返回已签名交易 hex。
  ///
  /// 输入：本人明文 UTXO（`rcpu1`，P2WPKH）+ 本人 CT UTXO（`rcpux1`，金额
  /// 经本地 unblind）；输出：收款方 CT（盲化到 `rcpux1` 内嵌公钥）+ 找零 CT
  /// （盲化到本人隐私路径公钥）。任何非 fee 输出缺 key → fail-closed。
  Future<String> _signCtPayment({
    required Address to,
    required int amountMicro,
    required String plainKeyHex,
    required String? ctKeyHex,
    required String? privateAddress,
    required String? plainAddress,
    required List<NativeUtxo>? utxos,
    required List<NativeUtxo>? ctUtxos,
    required int feeRateMicroPerByte,
    bool subtractFee = false,
  }) async {
    final helper = ctHelper;
    if (helper == null) {
      throw UnimplementedError('CT 代理未配置');
    }
    if (amountMicro <= 0) throw FormatException(AppStrings.current.amountMustBePositive);
    if (ctKeyHex == null || ctKeyHex.isEmpty) {
      throw FormatException(AppStrings.current.missingCtKey);
    }
    if (privateAddress == null || privateAddress.isEmpty) {
      throw FormatException(AppStrings.current.missingPrivateAddress);
    }
    final plainKey = _hexBytes(plainKeyHex);
    if (plainKey.length != 32) throw FormatException(AppStrings.current.plainKeyLen);
    final ctKey = _hexBytes(ctKeyHex);
    if (ctKey.length != 32) throw FormatException(AppStrings.current.ctKeyLen);

    // 收款方输出：rcpux1 内嵌 keyid -> P2WPKH 脚本；公钥 -> 盲化目标。
    final recipient = _decodePrivateAddress(to.value);
    final recipientScriptHex = '0014${recipient.keyidHex}';

    // 找零：本人隐私路径（盲化 key == spend key，同一把压缩公钥）。
    final ctPub = signature.compressedPubKey(ctKey);
    final changeScriptHex = '0014${_hex(Derivation.hash160(ctPub))}';

    // 1) 明文输入（rcpu1，仅 P2WPKH：CT 协处理器只支持 P2WPKH 输入脚本）。
    final plainPool = (utxos ??
            await nativeRpc.getUtxos(plainAddress ?? 'rcpu1'))
        .where((u) => u.confirmed && u.amountMicro > 0 && u.isP2wpkhInput)
        .toList();

    // 2) CT 输入（rcpux1：金额为 0 的盲化输出先 unblind；已可读金额则直接用）。
    final ctPool = await _resolveCtInputs(
      ctUtxos ?? await nativeRpc.getUtxos(privateAddress),
      ctKey,
    );

    final candidates = <_CtInput>[
      for (final u in plainPool)
        _CtInput(
          prevTxid: u.prevTxid,
          vout: u.vout,
          amountMicro: u.amountMicro,
          blindHex: null,
          scriptPubKeyHex: u.scriptPubKey,
          signKey: plainKey,
        ),
      ...ctPool,
    ]..sort((a, b) => a.amountMicro.compareTo(b.amountMicro));
    if (candidates.isEmpty) {
      throw StateError(AppStrings.current.noSpendableUtxo);
    }

    // 3) UTXO 选择：最大付款花费全部输入；否则最小足够集合（按「金额 +
    // 保守手续费」凑足）。
    final List<_CtInput> selected;
    var total = 0;
    int reservedFee;
    if (subtractFee) {
      selected = candidates;
      for (final c in selected) {
        total += c.amountMicro;
      }
      reservedFee = _estimateCtFee(selected.length, feeRateMicroPerByte);
    } else {
      selected = <_CtInput>[];
      for (final c in candidates) {
        selected.add(c);
        total += c.amountMicro;
        if (total >= amountMicro + _estimateCtFee(selected.length, feeRateMicroPerByte)) {
          break;
        }
      }
      reservedFee = _estimateCtFee(selected.length, feeRateMicroPerByte);
      if (total < amountMicro + reservedFee) {
        throw StateError(AppStrings.current.insufficient(
            Amount.fromMicro(total), Amount.fromMicro(amountMicro)));
      }
    }

    // 最大付款：手续费从金额里扣（无找零）；普通付款：找零差额归 fee。
    var payMicro = subtractFee ? total - reservedFee : amountMicro;
    if (payMicro <= 0) {
      throw StateError(AppStrings.current.insufficientWithFee);
    }

    // 4) 构造（找零 CT）；手续费由输入的显式输出补足。
    var change = subtractFee ? 0 : total - payMicro - reservedFee;
    final buildInputs = [for (final s in selected) s.toBuildInput()];
    List<CtBuildOutput> outputs = _ctOutputs(
      recipientScriptHex: recipientScriptHex,
      recipientBlindingHex: recipient.blindingPubHex,
      amountMicro: payMicro,
      changeScriptHex: changeScriptHex,
      changeBlindingHex: _hex(ctPub),
      changeMicro: change,
    );
    var built = await helper.build(inputs: buildInputs, outputs: outputs);

    // 5) 用实际（无 witness）交易尺寸校正手续费，不足则重建一次。
    var neededFee = _actualCtFeeMicro(
        built.txNoWitnessHex, selected.length, feeRateMicroPerByte);
    if (neededFee > reservedFee) {
      reservedFee = neededFee;
      if (subtractFee) {
        payMicro = total - reservedFee;
        change = 0;
      } else {
        change = total - payMicro - reservedFee;
      }
      if (payMicro <= 0 || change < 0) {
        throw StateError(AppStrings.current.insufficientWithFee);
      }
      outputs = _ctOutputs(
        recipientScriptHex: recipientScriptHex,
        recipientBlindingHex: recipient.blindingPubHex,
        amountMicro: payMicro,
        changeScriptHex: changeScriptHex,
        changeBlindingHex: _hex(ctPub),
        changeMicro: change,
      );
      built = await helper.build(inputs: buildInputs, outputs: outputs);
      final reNeeded = _actualCtFeeMicro(
          built.txNoWitnessHex, selected.length, feeRateMicroPerByte);
      if (reNeeded > reservedFee) {
        // 罕见的 range proof 尺寸波动导致仍不足：fail-closed，避免广播欠费交易。
        throw StateError(AppStrings.current.feeUnderestimated);
      }
    }

    // 5b) 安全校验：锚定未签名交易与本地付款意图一致（fail-closed）。
    // CT 协处理器经明文 HTTP 返回待签交易与 sighash 摘要，若不校验，路径
    // 攻击者可替换收款脚本并附上匹配摘要诱导设备签名（资金重定向）。逐项：
    // 1. 输入 outpoint 集合 == 本地选择的输入；
    // 2. 恰好 1 个输出脚本 == 收款脚本；change>0 时恰好 1 个 == 找零脚本；
    // 3. 其余输出（显式手续费）明文价值 ≤ 3×reservedFee。
    _verifyCtTxAnchors(
      txNoWitnessHex: built.txNoWitnessHex,
      selected: selected,
      recipientScriptHex: recipientScriptHex,
      changeScriptHex: changeScriptHex,
      changeMicro: change,
      reservedFee: reservedFee,
    );

    // 6) 逐输入签名（明文输入用明文私钥，CT 输入用隐私私钥），拼 witness。
    if (built.vin != selected.length) {
      throw StateError(AppStrings.current.ctInputMismatch);
    }
    final stacks = <List<Uint8List>>[];
    for (var i = 0; i < selected.length; i++) {
      final digest = _hexBytes(built.digests[i]);
      final key = selected[i].signKey;
      stacks.add([
        signature.signEcdsaDigest(key, digest),
        signature.compressedPubKey(key),
      ]);
    }
    return _spliceWitness(built.txNoWitnessHex, stacks);
  }

  /// 锚定校验：服务器返回的未签名交易必须与本地付款意图一致，任一不符
  /// 即抛 [StateError] 中止签名（见调用点注释）。多重集比较容忍输入重排。
  void _verifyCtTxAnchors({
    required String txNoWitnessHex,
    required List<_CtInput> selected,
    required String recipientScriptHex,
    required String changeScriptHex,
    required int changeMicro,
    required int reservedFee,
  }) {
    final tx = NativeTxCodec.parseHex(txNoWitnessHex);

    // 1) 输入一致性。
    if (tx.inputs.length != selected.length) {
      throw StateError(AppStrings.current.ctInputMismatch);
    }
    bool sameBytes(Uint8List a, Uint8List b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    final used = List<bool>.filled(selected.length, false);
    for (final inp in tx.inputs) {
      var hit = false;
      for (var j = 0; j < selected.length; j++) {
        if (!used[j] &&
            sameBytes(inp.prevTxid, selected[j].prevTxid) &&
            inp.prevVout == selected[j].vout) {
          used[j] = true;
          hit = true;
          break;
        }
      }
      if (!hit) {
        throw StateError(AppStrings.current.ctOutputMismatch);
      }
    }

    // 2) 输出锚定：收款/找零脚本必须恰好出现预期次数。
    var recipientCount = 0;
    var changeCount = 0;
    final extraIdx = <int>[];
    for (var i = 0; i < tx.outputs.length; i++) {
      final h = NativeTxCodec.bytesToHex(tx.outputs[i].scriptPubKey);
      if (h == recipientScriptHex) {
        recipientCount++;
      } else if (h == changeScriptHex) {
        changeCount++;
      } else {
        extraIdx.add(i);
      }
    }
    final expectChange = changeMicro > 0 ? 1 : 0;
    if (recipientCount != 1 || changeCount != expectChange) {
      throw StateError(AppStrings.current.ctOutputMismatch);
    }

    // 3) 其余输出 = 显式手续费（协议固定 1 个）：明文价值不得超预算。
    if (extraIdx.length != 1) {
      throw StateError(AppStrings.current.ctOutputMismatch);
    }
    final feeOut = tx.outputs[extraIdx.single];
    if (feeOut.value > BigInt.from(reservedFee * 3)) {
      throw StateError(AppStrings.current.ctOutputMismatch);
    }
  }

  /// 构造 CT 输出列表：收款 CT + 可选找零 CT。
  static List<CtBuildOutput> _ctOutputs({
    required String recipientScriptHex,
    required String recipientBlindingHex,
    required int amountMicro,
    required String changeScriptHex,
    required String changeBlindingHex,
    required int changeMicro,
  }) {
    return [
      CtBuildOutput(
        scriptPubKeyHex: recipientScriptHex,
        amountMicro: amountMicro,
        blindingPubHex: recipientBlindingHex,
      ),
      if (changeMicro > 0)
        CtBuildOutput(
          scriptPubKeyHex: changeScriptHex,
          amountMicro: changeMicro,
          blindingPubHex: changeBlindingHex,
        ),
    ];
  }

  /// 解析某个 `rcpux1` 地址的 UTXO 列表为可花费 CT 输入。
  ///
  /// 金额为 0（`scantxoutset` 读不到 CT 金额）或标记为 `ct`（代理已 unblind
  /// 金额但未回传盲因子）→ 经 `getrawtransaction` + `/ct/xctout` + 本地
  /// ECDH/HKDF + `/ct/rewind` 同时还原金额与盲因子；显式明文输出（`plain`）
  /// → 直接作为明文输入。非本人/不可解输出跳过。
  Future<List<_CtInput>> _resolveCtInputs(
      List<NativeUtxo> utxos, Uint8List ctKey) async {
    final helper = ctHelper;
    if (helper == null) return const [];
    final ctPub = signature.compressedPubKey(ctKey);
    final keyidHex = _hex(Derivation.hash160(ctPub));
    final resolver = CtResolver(nativeRpc, ctHelper: helper);
    final out = <_CtInput>[];
    for (final u in utxos) {
      if (!u.confirmed) continue;
      if (u.scriptPubKey.toLowerCase() != '0014$keyidHex') continue; // 非本人
      // 只有显式明文输出可直接作为明文输入；机密输出必须解出盲因子，
      // 否则 helper 会按显式 prevout 构造承诺，导致 VerifyAmounts / 节点
      // 校验失败（bad-txns-v2-spend-ct）。
      if (u.privacy != 'ct' && u.amountMicro > 0) {
        out.add(_CtInput(
          prevTxid: u.prevTxid,
          vout: u.vout,
          amountMicro: u.amountMicro,
          blindHex: null,
          scriptPubKeyHex: u.scriptPubKey,
          signKey: ctKey,
        ));
        continue;
      }
      final txidDisplay =
          _hex(Uint8List.fromList(u.prevTxid.reversed.toList()));
      final secret = await resolver.resolveUtxoSecret(
        txidDisplayHex: txidDisplay,
        vout: u.vout,
        spendPriv32: ctKey,
      );
      if (secret == null) continue; // 非本人输出，跳过
      out.add(_CtInput(
        prevTxid: u.prevTxid,
        vout: u.vout,
        amountMicro: secret.amountMicro,
        blindHex: secret.blindHex,
        scriptPubKeyHex: secret.scriptPubKeyHex,
        signKey: ctKey,
      ));
    }
    return out;
  }

  /// CT 交易手续费保守估算（micro）。
  ///
  /// range proof 是体积主体（占 base 区，非 witness）：按 3600 B / CT 输出
  /// 保守估值；构建后用真实尺寸校正（见 [_actualCtFeeMicro]）。
  int _estimateCtFee(int nIn, int feeRate) {
    final vsize = _ctVsize(
      baseBytes: 4 /*version*/ +
          2 /*marker+flag*/ +
          1 /*vin varint*/ +
          nIn * (32 + 4 + 1 + 4) +
          1 /*vout varint*/ +
          2 * 3600 /*2 个 CT 输出（收款 + 找零）*/ +
          9 /*显式手续费输出*/ +
          4 /*locktime*/,
      nIn: nIn,
    );
    return vsize * feeRate;
  }

  /// 依据实际返回交易尺寸计算所需手续费（micro），含 +8 vbyte 安全余量。
  int _actualCtFeeMicro(String txNoWitnessHex, int nIn, int feeRate) {
    final baseBytes = txNoWitnessHex.length ~/ 2 + 2 /*marker+flag*/;
    final vsize = _ctVsize(baseBytes: baseBytes, nIn: nIn);
    return (vsize + 8) * feeRate;
  }

  /// vsize = base（全 weight 4）+ witness（weight 1）/4。
  /// witness 按 P2WPKH 保守 111 B/输入（签名 ~73 + 压缩公钥 33）。
  static int _ctVsize({required int baseBytes, required int nIn}) {
    final witness = nIn * 111;
    return baseBytes + (witness + 3) ~/ 4;
  }

  /// 把 witness 栈拼进无 witness 交易：version || 0001 || vin||vout || witness || locktime。
  static String _spliceWitness(
      String noWitnessHex, List<List<Uint8List>> stacks) {
    if (noWitnessHex.length < 16) {
      throw FormatException(AppStrings.current.ctHexTooShort);
    }
    final version = noWitnessHex.substring(0, 8);
    final locktime = noWitnessHex.substring(noWitnessHex.length - 8);
    final body = noWitnessHex.substring(8, noWitnessHex.length - 8);
    final w = StringBuffer();
    for (final stack in stacks) {
      w.write(NativeTxCodec.bytesToHex(NativeTxCodec.encodeVarInt(stack.length)));
      for (final item in stack) {
        w.write(NativeTxCodec.bytesToHex(NativeTxCodec.encodeVarInt(item.length)));
        w.write(NativeTxCodec.bytesToHex(item));
      }
    }
    // BIP144 顺序：version || 0001(marker/flag) || vin||vout || witness || locktime。
    // helper 的 TX_NO_WITNESS 为 version||vin||vout||locktime，witness 必须插在
    // vout 与 locktime 之间，而非紧跟 version。
    return '${version}0001$body$w$locktime';
  }

  /// 解码 `rcpux1` 地址：返回内嵌 keyid（hex）与盲化公钥（压缩 33B hex）。
  ///
  /// 校验约束（path-c-spec §3）：keyid 必须等于 HASH160(pub)，否则 fail-closed。
  static ({String keyidHex, String blindingPubHex}) _decodePrivateAddress(
      String address) {
    final payload = Bech32.decodeToBytes(address.toLowerCase(), isBech32m: true);
    if (payload.length != 54 || payload[0] != 0x00) {
      throw FormatException(AppStrings.current.ctPayloadInvalid);
    }
    final keyid = payload.sublist(1, 21);
    final pub = payload.sublist(21, 54);
    if (pub[0] != 2 && pub[0] != 3) {
      throw FormatException(AppStrings.current.ctPubInvalid);
    }
    if (!_bytesEqual(Derivation.hash160(pub), keyid)) {
      throw FormatException(AppStrings.current.ctKeyidMismatch);
    }
    return (keyidHex: _hex(keyid), blindingPubHex: _hex(pub));
  }

  /// ================================================================ //
  /// 明文（plaintext）支付通路（已有，保持不变）
  /// ================================================================ //

  /// 构造原生明文收款交易（真实 UTXO 选择 + 输出构造 + fee）。
  ///
  /// - **输入**：仅选 [utxos] 中 P2TR（`0x51 0x20 || x-only`）、已确认的
  ///   可签名输出（BIP341 key-path 花费）或 P2WPKH（BIP143）；按需凑足
  ///   「金额 + 手续费」，避免暴露全部余额（最小足够集合）。
  /// - **收款输出**：明文 `rcpu1` → P2WPKH（`0x00 0x14 || h160`）。
  /// - **找零输出**：[changeAddress]（明文 P2WPKH）；差额归 fee。
  /// - **隐私收款**（`rcpux1`）：由 [confirmAndPay] 分派至 CT 通路，此处
  ///   fail-closed 抛 [UnimplementedError]（不静默降明文）。
  /// - [txHex] 为**未签名**交易；[prevOuts] 与输入一一对应。
  /// - 公开可见：TC-PAY-01 直测；wRCPU 桥路径复用。
  Future<BuiltNativeTx> buildNativeTxHex({
    required String toAddress,
    required int amountMicro,
    required String? fromAddress,
    String? changeAddress,
    List<NativeUtxo>? utxos,
    required int feeRateMicroPerByte,
    bool subtractFee = false,
  }) async {
    if (amountMicro <= 0) {
      throw FormatException(AppStrings.current.amountMustBePositive);
    }
    final to = Address.parse(toAddress);
    if (to.isPrivate) {
      throw UnimplementedError('隐私收款需 CT 盲化回填');
    }
    if (!to.isPlain) {
      throw FormatException(AppStrings.current.onlyPlainRecv);
    }
    if (fromAddress == null || fromAddress.isEmpty) {
      throw FormatException(AppStrings.current.missingFromAddress);
    }
    final change = Address.parse(changeAddress ?? fromAddress);
    if (!change.isPlain) {
      throw FormatException(AppStrings.current.changeMustBePlain);
    }

    // 拉取 UTXO（测试可注入；生产走 get_utxos 代理）。
    // amountMicro > 0：scantxoutset 对 CT 盲化输出读不出金额（返回 0），
    // 混入输入会触发节点 -26 bad-txns-v2-spend-ct（非 CT 交易花 CT 输出）。
    final pool = (utxos ?? await nativeRpc.getUtxos(fromAddress))
        .where((u) =>
            u.confirmed &&
            u.amountMicro > 0 &&
            (u.isP2wpkhInput || u.isP2trInput))
        .toList()
      ..sort((a, b) => a.amountMicro.compareTo(b.amountMicro));
    if (pool.isEmpty) {
      throw StateError(AppStrings.current.noSpendableP2wpkh);
    }

    final toScript = _p2wpkhScript(to);
    final changeScript = _p2wpkhScript(change);

    // 1) UTXO 选择：最大付款花费全部可用输出；否则最小足够集合（升序累加）。
    List<NativeUtxo> selected;
    BigInt total;
    int fee;
    BigInt effectiveAmount;
    if (subtractFee) {
      selected = pool;
      total = BigInt.zero;
      for (final u in selected) {
        total += BigInt.from(u.amountMicro);
      }
      // 手续费从付款金额里扣：单输出、无找零。
      fee = _estimateFee(selected.length, 1, feeRateMicroPerByte);
      effectiveAmount = total - BigInt.from(fee);
      if (effectiveAmount <= BigInt.zero) {
        throw StateError(AppStrings.current.insufficientWithFee);
      }
    } else {
      selected = <NativeUtxo>[];
      total = BigInt.zero;
      const assumedOutputs = 2; // 收款 + 找零（保守估值）
      for (final u in pool) {
        selected.add(u);
        total += BigInt.from(u.amountMicro);
        final f = _estimateFee(selected.length, assumedOutputs, feeRateMicroPerByte);
        if (total >= BigInt.from(amountMicro) + BigInt.from(f)) break;
      }
      fee = _estimateFee(selected.length, assumedOutputs, feeRateMicroPerByte);
      if (total < BigInt.from(amountMicro) + BigInt.from(fee)) {
        throw StateError(AppStrings.current.insufficient(
            Amount.fromMicro(total.toInt()), Amount.fromMicro(amountMicro)));
      }
      effectiveAmount = BigInt.from(amountMicro);
    }

    // 2) 输出构造（找零差额归 fee；最大付款无找零、手续费精确扣自金额）。
    var outputs = <NativeTxOut>[
      NativeTxOut(value: effectiveAmount, scriptPubKey: toScript),
    ];
    var changeMicro = total - effectiveAmount - BigInt.from(fee);
    if (changeMicro > BigInt.zero && !subtractFee) {
      outputs = [
        ...outputs,
        NativeTxOut(value: changeMicro, scriptPubKey: changeScript),
      ];
    } else if (!subtractFee) {
      // 无找零：fee = total - amount（全部视为手续费，需为正）
      final actualFee = total - effectiveAmount;
      if (actualFee < BigInt.zero) {
        throw StateError(AppStrings.current.insufficientWithFee);
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

  /// 明文地址 → P2WPKH 锁定脚本（`0x00 0x14 || program`，22 字节）。
  ///
  /// rcpu1 为 BIP173 witness v0：version group 与 program 分组解析。
  Uint8List _p2wpkhScript(Address addr) {
    final w = Bech32.decodeWitness(addr.value);
    if (w.version != 0 || w.program.length != 20) {
      throw FormatException(AppStrings.current.plainMustBeV0);
    }
    return Uint8List.fromList([0x00, 0x14, ...w.program]);
  }

  /// 估算交易 vsize 并乘费率：base + witness/4。witness 按保守值
  /// 110B/输入（P2WPKH：签名 ~73B + 压缩公钥 33B；P2TR 仅 66B，
  /// 统一取大者避免低估手续费）。返回 micro 手续费。
  int _estimateFee(int nIn, int nOut, int feeRateMicroPerByte) {
    final base = 4 /*version*/ +
        1 /*vin varint*/ +
        nIn * (32 + 4 + 1 + 4) + // outpoint + scriptSigLen(1) + seq
        1 /*vout varint*/ +
        nOut * (8 + 1 + 22) + // value + scriptLen + P2WPKH(22)
        4 /*locktime*/;
    final witness = nIn * 110; // 栈项数 + 签名(~73B) + 压缩公钥(33B)
    final vsize = base + (witness + 3) ~/ 4;
    return vsize * feeRateMicroPerByte;
  }

  /// 估算「最大付款」可转金额（micro）：全部可用输入 − 手续费（无找零）。
  ///
  /// 供发送页 MAX 按钮回填；与 [subtractFee] 构建路径保持同一口径。
  /// - 明文收款（`rcpu1`）：仅明文 UTXO，按单输出明文交易估费；
  /// - 隐私收款（`rcpux1`，传 [privateAddress] + [ctPrivateKeyHex]）：
  ///   明文 P2WPKH + 隐私地址 CT 输入一并计入，按 CT 交易保守估费
  ///   （实付金额在构建时按真实尺寸再校正）。
  /// 无可用输出或余额不足以覆盖手续费时返回 0。
  Future<int> estimateMaxSendableMicro(
    String fromAddress, {
    int feeRateMicroPerByte = defaultFeeRateMicroPerByte,
    String? privateAddress,
    String? ctPrivateKeyHex,
  }) async {
    final plainUtxos = (await nativeRpc.getUtxos(fromAddress))
        .where((u) => u.confirmed && u.amountMicro > 0)
        .toList();

    // 隐私收款：CT 路径（含 CT 输入解盲）。
    if (privateAddress != null &&
        privateAddress.isNotEmpty &&
        ctPrivateKeyHex != null &&
        ctHelper != null) {
      final ctKey = _hexBytes(ctPrivateKeyHex);
      var total = 0;
      var nIn = 0;
      for (final u in plainUtxos.where((u) => u.isP2wpkhInput)) {
        total += u.amountMicro;
        nIn++;
      }
      final ctPool = await _resolveCtInputs(
          await nativeRpc.getUtxos(privateAddress), ctKey);
      for (final c in ctPool) {
        total += c.amountMicro;
        nIn++;
      }
      if (nIn == 0) return 0;
      final max = total - _estimateCtFee(nIn, feeRateMicroPerByte);
      return max > 0 ? max : 0;
    }

    // 明文路径。
    final pool = plainUtxos
        .where((u) => u.isP2wpkhInput || u.isP2trInput)
        .toList();
    if (pool.isEmpty) return 0;
    var total = 0;
    for (final u in pool) {
      total += u.amountMicro;
    }
    final fee = _estimateFee(pool.length, 1, feeRateMicroPerByte);
    final max = total - fee;
    return max > 0 ? max : 0;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexBytes(String hex) {
    final h = hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();
    if (h.length.isOdd) throw FormatException(AppStrings.current.hexOdd);
    if (h.isEmpty) return Uint8List(0);
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}

/// CT 输入描述（明文或盲化 prevout），含签名所需私钥。
class _CtInput {
  final Uint8List prevTxid; // 内部字节序
  final int vout;
  final int amountMicro;
  final String? blindHex; // null = 显式（明文）输入
  final String scriptPubKeyHex;
  final Uint8List signKey;

  const _CtInput({
    required this.prevTxid,
    required this.vout,
    required this.amountMicro,
    required this.blindHex,
    required this.scriptPubKeyHex,
    required this.signKey,
  });

  CtBuildInput toBuildInput() => CtBuildInput(
        txidHex: prevTxid.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        vout: vout,
        amountMicro: amountMicro,
        blindHex: blindHex,
        scriptPubKeyHex: scriptPubKeyHex,
      );
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

