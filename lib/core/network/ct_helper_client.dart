import 'dart:typed_data';

import 'package:dio/dio.dart';

/// CT 盲化协处理器（服务器侧 secp256k1-zkp）HTTP 客户端。
///
/// 服务器（nginx `/ct/` → 127.0.0.1:8819 → `_ct_helper`）暴露三条命令：
/// - `build`：为输出生成 Pedersen 承诺 + range proof（默认 Path C，`0x04`
///   nonce），追加显式手续费输出，返回**未签名**交易 hex 与各输入的 BIP143
///   sighash 摘要；
/// - `rewind`：用**客户端本地** ECDH/HKDF 推导出的 rewind nonce 解出金额与
///   盲因子；
/// - `xctout`：解析链上 CT 输出，取出 commitment / rangeproof / nonce 字段，
///   供客户端重建 ephemeral 公钥做本地 ECDH。
///
/// 安全边界：私钥永不离开设备。`build` 只产出摘要（签名在 App 内完成），
/// `rewind` 只接受客户端算出的 32B nonce（不含任何密钥）。
class CtHelperException implements Exception {
  final String message;

  /// 网络 / 超时类错误（可重试）；协议类错误为 false（重试无意义）。
  final bool transient;

  const CtHelperException(this.message, {this.transient = false});

  @override
  String toString() => 'CtHelperException: $message';
}

/// CT 构造输入（一个待花费的 prevout）。
class CtBuildInput {
  /// 前一交易 hash，**内部字节序** hex（与交易序列化一致，32B）。
  final String txidHex;
  final int vout;

  /// 明文金额（micro）。CT 输入填经 rewind 还原的金额。
  final int amountMicro;

  /// 盲因子 hex（32B）；`null` 或空串表示显式（明文）输入。
  final String? blindHex;

  /// prevout 锁定脚本 hex（P2WPKH `0014||h160`，22B）。
  final String scriptPubKeyHex;

  const CtBuildInput({
    required this.txidHex,
    required this.vout,
    required this.amountMicro,
    required this.scriptPubKeyHex,
    this.blindHex,
  });

  Map<String, dynamic> toJson() => {
        'txid_hex': txidHex,
        'vout': vout,
        'amount_micro': amountMicro,
        'blind_hex': blindHex ?? '',
        'script_pubkey_hex': scriptPubKeyHex,
      };
}

/// CT 构造输出。
class CtBuildOutput {
  /// 输出锁定脚本 hex（P2WPKH）。
  final String scriptPubKeyHex;
  final int amountMicro;

  /// 收款方盲化公钥 hex（33B 压缩点）；`null` 表示显式（明文）输出。
  final String? blindingPubHex;

  const CtBuildOutput({
    required this.scriptPubKeyHex,
    required this.amountMicro,
    this.blindingPubHex,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'script_pubkey_hex': scriptPubKeyHex,
      'amount_micro': amountMicro,
    };
    if (blindingPubHex != null && blindingPubHex!.isNotEmpty) {
      m['blinding_pub_hex'] = blindingPubHex;
    }
    return m;
  }
}

/// `build` 单个输出元数据。
class CtOutputMeta {
  final int vout;
  final bool confidential;
  final String blindHex;

  const CtOutputMeta({
    required this.vout,
    required this.confidential,
    required this.blindHex,
  });
}

/// `build` 结果：未签名交易 + 各输入签名摘要。
class CtBuildResult {
  /// 无 witness 序列化 hex（version||vin||vout||locktime）；App 侧拼 witness。
  final String txNoWitnessHex;
  final int vin;
  final int vout;
  final int feeMicro;

  /// 各输入的 32B BIP143 SIGHASH_ALL 摘要 hex（与输入一一对应）。
  final List<String> digests;
  final List<CtOutputMeta> outputsMeta;

  const CtBuildResult({
    required this.txNoWitnessHex,
    required this.vin,
    required this.vout,
    required this.feeMicro,
    required this.digests,
    required this.outputsMeta,
  });
}

/// `rewind` 结果。
class CtRewindResult {
  final int amountMicro;
  final String blindHex;

  const CtRewindResult({required this.amountMicro, required this.blindHex});
}

/// `xctout` 结果：链上 CT 输出的拆解字段。
class CtOutputFields {
  /// 33B Pedersen 承诺（value commitment）hex。
  final String commitmentHex;

  /// range proof hex。
  final String rangeproofHex;

  /// nonce 前缀：0x02 = Path A（禁用）、0x03 = Path B、0x04 = Path C。
  final int noncePrefix;

  /// nonce 携带的 32B X 坐标 hex。
  final String nonceXHex;

  /// 该输出的锁定脚本 hex。
  final String scriptPubKeyHex;

  const CtOutputFields({
    required this.commitmentHex,
    required this.rangeproofHex,
    required this.noncePrefix,
    required this.nonceXHex,
    required this.scriptPubKeyHex,
  });
}

class CtHelperClient {
  /// 基础端点（不含尾斜杠），默认生产服务器 `/ct`。
  final String endpoint;

  late final Dio _dio;

  CtHelperClient({this.endpoint = 'https://rcpu.cloud/ct'}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      // 盲化 + range proof 生成较重，放宽至 60s。
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  Future<Map<String, dynamic>> _post(
      String sub, Map<String, dynamic> body) async {
    // 境外线路抖动：连接类错误线性退避重试 2 次（盲化请求无副作用）。
    for (var attempt = 1;; attempt++) {
      try {
        return await _postOnce(sub, body);
      } on CtHelperException catch (e) {
        if (!e.transient || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
  }

  Future<Map<String, dynamic>> _postOnce(
      String sub, Map<String, dynamic> body) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.post('$endpoint/$sub', data: body);
    } on DioException catch (e) {
      // 代理/helper 失败时 body 仍为 JSON（{"error": "..."}），优先透传。
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        throw CtHelperException(data['error'].toString());
      }
      if (data is String && data.isNotEmpty) {
        throw CtHelperException(
          data.length > 200 ? data.substring(0, 200) : data,
          transient: true,
        );
      }
      final status = e.response?.statusCode;
      throw CtHelperException(
        status != null ? 'CT 服务 HTTP $status: ${e.message}' : 'CT 服务不可达: ${e.message ?? e.type}',
        transient: true,
      );
    }
    final data = resp.data;
    if (data is! Map) {
      throw const CtHelperException('CT 服务返回非 JSON 响应');
    }
    if (data['error'] != null) {
      throw CtHelperException(data['error'].toString());
    }
    return data.cast<String, dynamic>();
  }

  /// 生成盲化输出交易（Path C）。
  Future<CtBuildResult> build({
    required List<CtBuildInput> inputs,
    required List<CtBuildOutput> outputs,
  }) async {
    if (inputs.isEmpty) throw const CtHelperException('至少需要一个输入');
    if (outputs.isEmpty) throw const CtHelperException('至少需要一个输出');
    final json = await _post('build', {
      'inputs': [for (final i in inputs) i.toJson()],
      'outputs': [for (final o in outputs) o.toJson()],
    });
    final txHex = json['tx_no_witness_hex'] as String?;
    final digests = (json['digests'] as List?)?.cast<String>() ?? const [];
    if (txHex == null || digests.length != inputs.length) {
      throw const CtHelperException('build 返回字段不完整');
    }
    final metas = <CtOutputMeta>[];
    for (final m in (json['outputs_meta'] as List?) ?? const []) {
      final mm = (m as Map).cast<String, dynamic>();
      metas.add(CtOutputMeta(
        vout: (mm['vout'] as num?)?.toInt() ?? 0,
        confidential: mm['confidential'] as bool? ?? false,
        blindHex: (mm['blind_hex'] ?? '').toString(),
      ));
    }
    return CtBuildResult(
      txNoWitnessHex: txHex,
      vin: (json['vin'] as num?)?.toInt() ?? inputs.length,
      vout: (json['vout'] as num?)?.toInt() ?? outputs.length,
      feeMicro: (json['fee_micro'] as num?)?.toInt() ?? 0,
      digests: digests,
      outputsMeta: metas,
    );
  }

  /// 用客户端推导的 rewind nonce 解出金额与盲因子。
  Future<CtRewindResult> rewind({
    required Uint8List nonce32,
    required Uint8List commitment33,
    required Uint8List rangeproof,
  }) async {
    if (nonce32.length != 32) throw const CtHelperException('nonce 须为 32B');
    if (commitment33.length != 33) {
      throw const CtHelperException('commitment 须为 33B');
    }
    final json = await _post('rewind', {
      'nonce_hex': _hex(nonce32),
      'commitment_hex': _hex(commitment33),
      'rangeproof_hex': _hex(rangeproof),
    });
    final amt = (json['amount_micro'] as num?)?.toInt();
    final blind = json['blind_hex'] as String?;
    if (amt == null || blind == null) {
      throw const CtHelperException('rewind 返回字段不完整');
    }
    return CtRewindResult(amountMicro: amt, blindHex: blind);
  }

  /// 解析链上交易某个输出，返回 CT 字段（commitment/rangeproof/nonce/脚本）。
  Future<CtOutputFields> xctout({
    required String txHex,
    required int vout,
  }) async {
    final json = await _post('xctout', {'tx_hex': txHex, 'vout': vout});
    final commit = json['commitment_hex'] as String?;
    final rp = json['rangeproof_hex'] as String?;
    final x = json['nonce_x_hex'] as String?;
    final spk = json['script_pubkey_hex'] as String?;
    if (commit == null || rp == null || x == null || spk == null) {
      throw const CtHelperException('xctout 返回字段不完整');
    }
    return CtOutputFields(
      commitmentHex: commit,
      rangeproofHex: rp,
      noncePrefix: (json['nonce_prefix'] as num?)?.toInt() ?? 0,
      nonceXHex: x,
      scriptPubKeyHex: spk,
    );
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
