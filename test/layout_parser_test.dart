import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testdeploy/main.dart';

void main() {
  test('layout parser reads the dummy certificate OCR output', () {
    final raw = File('test/fixtures/dummy_ocr.json').readAsStringSync();
    final r = parseOcrOutput(raw);
    expect(r.values['name'], 'أحمد');
    expect(r.values['gender'], 'ذكر');
    expect(r.values['birthPlace'], 'الجيزة / بولاق الدكرور');
    expect(r.values['childNat'], 'مصر');
    expect(r.values['fatherName'], 'محمد سعيد فتحي');
    expect(r.values['fatherNid'], '28022222200066');
    expect(r.values['fatherReligion'], 'مسلم');
    expect(r.values['fatherNat'], 'مصر');
    expect(r.values['motherNid'], '29522223200066');
    expect(r.values['motherReligion'], 'مسلمة');
    expect(r.values['motherNat'], 'مصر');
  });
}
