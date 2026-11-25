import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

Future<String> extractText(
  Uint8List bytes, {
  String language = 'ara+eng',
}) async {
  final dir = await Directory.systemTemp.createTemp('ocr_');
  final file = File('${dir.path}${Platform.pathSeparator}image.png');
  try {
    await file.writeAsBytes(bytes, flush: true);
    return await FlutterTesseractOcr.extractText(
      file.path,
      language: language,
    );
  } catch (e) {
    throw Exception(_readableError(e));
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

String _readableError(Object e) {
  final text = e.toString();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) {
    return text.substring(prefix.length);
  }
  return text;
}
