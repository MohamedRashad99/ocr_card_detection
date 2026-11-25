import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testdeploy/main.dart';

void main() {
  test('parse the real OCR text of the attached certificate', () {
    final text = File(
      r'C:\Users\Aca\AppData\Local\Temp\opencode\tess_best.txt',
    ).readAsStringSync();
    final result = CertificateParser.parse(text);
    // ignore: avoid_print
    print('VALUES: ${result.values}');
    // ignore: avoid_print
    print('NOTES: ${result.notes}');
    expect(result.values, isNotEmpty);
  });
}
