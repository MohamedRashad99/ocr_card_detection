import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:web/web.dart' as web;

const _runtimeScriptId = 'tesseract-runtime';
const _hookScriptId = 'tesseract-extract-hook';

const _extractTextJs = r'''
async function _extractText(imagePath, mapData) {
  try {
    if (typeof Tesseract === 'undefined') {
      throw new Error('Tesseract.js failed to load');
    }
    var base = document.baseURI;
    var workerPath = new URL('worker.min.js', base).href;
    var corePath = new URL('tesseract-core.wasm.js', base).href;
    var langPath = new URL('lang/', base).href.replace(/\/$/, '');
    var gzip = true;
    try {
      var probe = await fetch(langPath + '/ara.traineddata.gz');
      var encoding = (probe.headers.get('content-encoding') || '').toLowerCase();
      var buf = await probe.arrayBuffer();
      var u8 = new Uint8Array(buf);
      var magicGzip = u8.length >= 2 && u8[0] === 0x1f && u8[1] === 0x8b;
      gzip = magicGzip && encoding.indexOf('gzip') === -1;
    } catch (_) {}
    var worker = await Tesseract.createWorker({
      workerPath: workerPath,
      corePath: corePath,
      langPath: langPath,
      gzip: gzip,
      errorHandler: function (err) {
        console.error(err);
      }
    });
    try {
      var language = (mapData && mapData.language) ? mapData.language : 'ara+eng';
      await worker.loadLanguage(language);
      await worker.initialize(language);
      if (mapData && mapData.args) {
        await worker.setParameters(mapData.args);
      }
      var rtn = await worker.recognize(imagePath);
      if (mapData && mapData.args && mapData.args['tessjs_create_hocr']) {
        return rtn.data.hocr;
      }
      return rtn.data.text;
    } finally {
      await worker.terminate();
    }
  } catch (e) {
    var message = (e && e.message) ? e.message : String(e);
    throw new Error(message);
  }
}
''';

Future<String> extractText(
  Uint8List bytes, {
  String language = 'ara+eng',
}) async {
  await _ensureTesseractLoaded();
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  try {
    final result = await FlutterTesseractOcr.extractText(
      url,
      language: language,
    );
    return result.toString();
  } catch (e) {
    throw Exception(_readableError(e));
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

Future<void> _ensureTesseractLoaded() async {
  final document = web.document;
  final tesseractReady =
      globalContext.has('Tesseract') && globalContext['Tesseract'] != null;

  if (!tesseractReady) {
    document.getElementById(_runtimeScriptId)?.remove();
    final src = web.URL('tesseract.min.js', document.baseURI).href;
    final script = web.HTMLScriptElement()
      ..id = _runtimeScriptId
      ..type = 'text/javascript'
      ..src = src;
    final loaded = Completer<void>();
    script.addEventListener(
      'load',
      (web.Event _) {
        if (!loaded.isCompleted) loaded.complete();
      }.toJS,
    );
    script.addEventListener(
      'error',
      (web.Event _) {
        if (!loaded.isCompleted) {
          loaded.completeError(
            Exception('Failed to load tesseract.min.js from $src'),
          );
        }
      }.toJS,
    );
    document.head!.append(script);
    await loaded.future;
  }

  final hookReady =
      globalContext.has('_extractText') && globalContext['_extractText'] != null;
  if (!hookReady) {
    document.getElementById(_hookScriptId)?.remove();
    final hook = web.HTMLScriptElement()
      ..id = _hookScriptId
      ..type = 'text/javascript'
      ..text = _extractTextJs;
    document.head!.append(hook);
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
