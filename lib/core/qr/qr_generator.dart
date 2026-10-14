import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 二维码生成封装（qr_flutter）。
///
/// 协议：`rcpu:<address>?amount=<decimal>&asset=<native|wrcpu>&memo=<text>`
class QrGenerator {
  /// 构造 rcpu: URI。
  static String buildRcpuUri({
    required String address,
    String? amount,
    String? asset,
    String? memo,
  }) {
    final buffer = StringBuffer('rcpu:$address');
    final params = <String>[];
    if (amount != null && amount.isNotEmpty) {
      params.add('amount=$amount');
    }
    if (asset != null && asset.isNotEmpty) {
      params.add('asset=$asset');
    }
    if (memo != null && memo.isNotEmpty) {
      params.add('memo=${Uri.encodeComponent(memo)}');
    }
    if (params.isNotEmpty) {
      buffer.write('?${params.join('&')}');
    }
    return buffer.toString();
  }

  /// 渲染二维码为 Widget（收款页使用）。
  static Widget render(
    String data, {
    double size = 220,
    Color foreground = Colors.black,
    Color background = Colors.white,
  }) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      foregroundColor: foreground,
      backgroundColor: background,
      padding: EdgeInsets.zero,
      gapless: true,
    );
  }

  /// 导出为字节 PNG（保存/分享使用，需在 widget 绑定完成后调用）。
  static Future<ByteData> toPngBytes(String data, {double size = 220}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      color: Colors.black,
    );
    painter.paint(canvas, Size(size, size));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    return (await image.toByteData(format: ui.ImageByteFormat.png))!;
  }
}