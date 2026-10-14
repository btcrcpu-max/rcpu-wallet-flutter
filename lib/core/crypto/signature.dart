import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

/// 签名工具统一入口。
///
/// - [signNative]：原生 RCPU 交易签名（算法与链上协议对齐，待桥确认）
/// - [verifyBscSignature]：BSC/EVM 个人消息签名校验（EIP-191）
///
/// 密钥只驻留内存副本，不落盘。
class Signature {
  /// 原生链交易签名（占位：接入协议签名库后补齐）。
  Future<Uint8List> signNative(Uint8List tx, Uint8List privateKey) async {
    throw UnimplementedError('原生签名算法待协议文档确认');
  }

  /// 校验 BSC/EVM 个人消息签名（EIP-191：`\x19Ethereum Signed Message:\n<len>`）。
  ///
  /// [message] 为被签名的原始消息字节；[signature] 为标准 65 字节紧凑签名
  /// `r(32) || s(32) || v(1)`（v 取 `{0,1}` 或 `{27,28}`，自动归一化到 27/28）；
  /// [addressHex] 为期望的签名者地址（`0x` 前缀与大小写不敏感）。
  ///
  /// 实现：keccak256(personalMessage) -> `ecRecover` 恢复公钥
  /// -> `publicKeyToAddress` 得地址，与 [addressHex] 比对；
  /// 签名长度非法、恢复失败或地址不匹配返回 false。
  bool verifyBscSignature(
      Uint8List message, Uint8List signature, String addressHex) {
    if (signature.length != 65) return false;
    final v = signature[64] < 27 ? signature[64] + 27 : signature[64];
    final msgSig = MsgSignature(
      bytesToUnsignedInt(signature.sublist(0, 32)),
      bytesToUnsignedInt(signature.sublist(32, 64)),
      v,
    );
    try {
      final personalHash = keccak256(Uint8List.fromList([
        ...utf8.encode('\x19Ethereum Signed Message:\n${message.length}'),
        ...message,
      ]));
      final recoveredPub = ecRecover(personalHash, msgSig);
      final recovered = bytesToHex(publicKeyToAddress(recoveredPub));
      return recovered == _normHex(addressHex);
    } catch (_) {
      return false;
    }
  }

  /// 归一化十六进制地址：去 `0x` 前缀并转小写。
  static String _normHex(String input) {
    final v = input.trim().toLowerCase();
    return v.startsWith('0x') ? v.substring(2) : v;
  }
}

/// 原生交易签名服务（Path C 落地前占位）。
///
/// 与 [Signature] 的字节级接口不同，本类面向「交易 hex + 私钥 hex → 签名 hex」
/// 的高层入口，供支付链路（TC-SIG-03）调用；签名算法依赖 C1/C2 协议文档确认。
class SignatureService {
  /// 原生交易签名（Path C 落地前占位）。
  ///
  /// - 依赖 C1/C2：原生签名算法待协议文档确认；
  /// - 当前仅支持明文地址（rcpu1）支付；隐私地址（rcpux1）触发上层降级提示。
  Future<String> signNative(String txHex, String privateKeyHex) async {
    throw UnimplementedError(
      '原生签名算法待协议文档确认（C1/C2）。'
      '当前仅支持明文地址支付，请使用 rcpu1 地址。',
    );
  }
}