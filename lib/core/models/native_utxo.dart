import 'dart:typed_data';

/// 原生链未花费输出（UTXO）模型。
///
/// 由代理 `get_utxos`（docs/proxy-rpc-schema.md §方法五）返回：
/// 仅自有、未花费、已确认输出；CT 输出金额已由代理 unblind（`privacy=='ct'`）。
class NativeUtxo {
  /// 前一交易 hash，**内部字节序**（与交易序列化原样一致，32B）。
  final Uint8List prevTxid;

  /// 前一交易输出索引。
  final int vout;

  /// 可花费金额（micro，CT 已 unblind 后的明文值）。
  final int amountMicro;

  /// 该输出的锁定脚本 hex（明文 P2WPKH `0x00 0x14 || h160`；
  /// 可签名输入须为 P2TR `0x51 0x20 || x-only`）。
  final String scriptPubKey;

  /// 是否已确认（未确认输出不可花费）。
  final bool confirmed;

  /// plain / ct（ct 表示原始为机密输出，金额经 unblind）。
  final String privacy;

  const NativeUtxo({
    required this.prevTxid,
    required this.vout,
    required this.amountMicro,
    required this.scriptPubKey,
    this.confirmed = true,
    this.privacy = 'plain',
  });

  /// 从代理 JSON 记录构造。
  factory NativeUtxo.fromJson(Map<String, dynamic> json) {
    return NativeUtxo(
      prevTxid: _hexToBytes((json['txid'] ?? '').toString()),
      vout: (json['vout'] as num?)?.toInt() ?? 0,
      amountMicro: (json['amountMicro'] as num?)?.toInt() ?? 0,
      scriptPubKey: (json['scriptPubKey'] ?? '').toString(),
      confirmed: json['confirmed'] as bool? ?? true,
      privacy: (json['privacy'] ?? 'plain').toString(),
    );
  }

  /// 是否为 P2TR 可签名输入（`0x51 0x20 || x-only32`，34 字节）。
  bool get isP2trInput {
    final spk = _hexToBytes(scriptPubKey);
    return spk.length == 34 && spk[0] == 0x51 && spk[1] == 0x20;
  }

  /// 是否为 P2WPKH 可签名输入（`0x00 0x14 || h160`，22 字节）。
  ///
  /// BIP84 明文地址（rcpu1...）对应的链上输出形态；
  /// 签名走 BIP143 sighash + secp256k1 ECDSA（非 Schnorr）。
  bool get isP2wpkhInput {
    final spk = _hexToBytes(scriptPubKey);
    return spk.length == 22 && spk[0] == 0x00 && spk[1] == 0x14;
  }

  static Uint8List _hexToBytes(String hex) {
    final h = hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();
    if (h.isEmpty) return Uint8List(0);
    if (h.length.isOdd) throw const FormatException('hex 长度必须为偶数');
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}