import 'package:flutter_test/flutter_test.dart';
import 'package:testdeploy/main.dart';

void main() {
  group('CertificateParser', () {
    test('parses a clean certificate with child/father/mother sections', () {
      const text = '''
جمهورية مصر العربية
وزارة الداخلية
صورة قيد الميلاد
بيانات المولود
الاسم: احمد محمد سعيد
الديانة: مسلم
الجنسية: مصر
النوع: ذكر
محل الميلاد: الجيزة / بولاق الدكرور
تاريخ الميلاد: 22/02/1980
الرقم القومي: 28022222200066
بيانات الأب
محمد سعيد فتحي
الديانة: مسلم
الرقم القومي: 25011111200011
الجنسية: مصر
بيانات الأم
سارة فتحي محمد
الديانة: مسلمة
الرقم القومي: 28505050200022
الجنسية: مصر
رقم القيد: 5541
جهة القيد: بولاق الدكرور
تاريخ الإصدار: 25/08/2020
''';

      final result = CertificateParser.parse(text);

      expect(result.values['gender'], 'ذكر');
      expect(result.values['birthDate'], '22/02/1980');
      expect(result.values['birthPlace'], 'الجيزة - بولاق الدكرور');
      expect(result.values['fatherName'], 'محمد سعيد فتحي');
      expect(result.values['motherName'], 'سارة فتحي محمد');
      expect(result.values['fatherNat'], 'مصر');
      expect(result.values['motherNat'], 'مصر');
      expect(result.values['nid'], '28022222200066');
      expect(result.values['serial'], '5541');
      expect(result.values['registry'], 'بولاق الدكرور');
      expect(result.values['issueDate'], '25/08/2020');
      expect(result.values['childReligion'], 'مسلم');
      expect(result.values['childNat'], 'مصر');
      expect(result.values['fatherReligion'], 'مسلم');
      expect(result.values['motherReligion'], 'مسلمة');
      expect(result.values['fatherNid'], '25011111200011');
      expect(result.values['motherNid'], '28505050200022');
    });

    test('parses the noisy text extracted from the attached certificate', () {
      // Real OCR output (OCR.space) for the failing sample. The layout is
      // noisy: section headers and dates are mangled, and the parents' NIDs
      // are not labelled.
      const text = '''
مجد هم مجهم الحربير
وارية المجدية
قديه فالمصيحة والتنَدْدخَضُ
صورة قيد الميلاد
www.itss.gov.eg
بيَاتام الموتود
الديانه معالم
الجسميه : مصر
الحوع : 4 كر
محل الميلاد : الجيره / بولاق الدكرور
تاريح الميلاد : وامه وظلاتون مزمايم.
عام الق و شسعمانه و سحه و سسعون.
بَيَابَاملاب
محمد سعيد فتحي
الديانه : مسلم
28022222200066
الجنميه : مسر
بمَيَانَ م الأمرّ
سارة فتحي محمد
الديانه : مسلمة
الجنميه : مسر
29522223200066
رثم القيم : ٥٥٤١
م ء سة : بولاق الدكرور
ت. الطيه ١٩٧٥/٠٢/١٣
، بولاق الدكرور
بي : هيه نسي
ت. ٩ ممبار ٢٠٢٠٢/ ٠٨/٠٢٥٨
من ء امد آن : محل فدبيعه نحر اول
''';

      final result = CertificateParser.parse(text);

      expect(result.values['gender'], 'ذكر');
      expect(result.values['birthPlace'], 'الجيزة - بولاق الدكرور');
      expect(result.values['fatherName'], 'محمد سعيد فتحي');
      expect(result.values['motherName'], 'سارة فتحي محمد');
      expect(result.values['fatherNat'], 'مصر');
      expect(result.values['motherNat'], 'مصر');
      expect(result.values['serial'], '5541');
      expect(result.values['registry'], 'بولاق الدكرور');
      expect(result.values['issueDate'], '25/08/2020');

      // Never reuse a parent's number as the child's NID.
      expect(result.values['nid'], isNull);
      expect(result.values['birthDate'], isNull);
      expect(
        result.notes.any((n) => n.contains('الرقم القومي')),
        isTrue,
      );
      expect(result.values['childReligion'], 'مسلم');
      expect(result.values['fatherReligion'], 'مسلم');
      expect(result.values['motherReligion'], 'مسلمة');
      expect(result.values['fatherNid'], '28022222200066');
      expect(result.values['motherNid'], '29522223200066');
    });

    test('decodes a valid national ID and rejects an invalid one', () {
      final info = CertificateParser.decodeNid('30103141200017');
      expect(info, isNotNull);
      expect(info!.birthDate, '14/03/2001');
      expect(info.gender, 'ذكر');
      expect(info.governorate, 'الدقهلية');

      // OCR-mangled NID: month 22 is impossible, so it must not be used to
      // derive the child's birth date or gender.
      expect(CertificateParser.decodeNid('28022222200066'), isNull);
      expect(CertificateParser.decodeNid('29522223200066'), isNull);
      expect(CertificateParser.decodeNid('123'), isNull);
    });

    test('handles a plain label/value certificate without section headers', () {
      const text = '''
اسم المولود: يوسف علي حسن
النوع: ذكر
محل الميلاد: القاهرة / مدينة نصر
تاريخ الميلاد: 2021/03/14
اسم الأب: علي حسن محمود
جنسية الأب: مصر
اسم الأم: هدى إبراهيم سعيد
جنسية الأم: مصر
الرقم القومي: 30103141200017
المسلسل: 9087
''';

      final result = CertificateParser.parse(text);

      expect(result.values['name'], 'يوسف علي حسن');
      expect(result.values['gender'], 'ذكر');
      expect(result.values['birthPlace'], 'القاهرة - مدينة نصر');
      expect(result.values['birthDate'], '14/03/2021');
      expect(result.values['fatherName'], 'علي حسن محمود');
      expect(result.values['motherName'], 'هدى إبراهيم سعيد');
      expect(result.values['fatherNat'], 'مصر');
      expect(result.values['motherNat'], 'مصر');
      expect(result.values['nid'], '30103141200017');
      expect(result.values['serial'], '9087');
    });
    test('reads a birth date spelled out in Arabic words', () {
      const text = '''
بيانات المولود
الاسم: احمد محمد سعيد
النوع: ذكر
محل الميلاد: الجيزة / بولاق الدكرور
تاريخ الميلاد: واحد وثلاثون ديسمبر
عام ألف وتسعمائة وستة وسبعون
''';

      final result = CertificateParser.parse(text);
      expect(result.values['birthDate'], '31/12/1976');
    });

    test('reads a noisy spelled-out birth date with glued tokens', () {
      const text = '''
بيانات المولود
النوع: ذكر
تاريخ الميلاد: واحده وثلاثون ديسمبر
عام الق و شسعمانه و سحه و سسعون.
''';

      final result = CertificateParser.parse(text);
      expect(result.values['birthDate'], '31/12/1976');
    });

    test('keeps every certificate field in the field list', () {
      const expected = <String>{
        'serial', 'issueDate', 'nid', 'name', 'gender', 'birthDate',
        'birthPlace', 'fatherName', 'motherName', 'fatherNat', 'motherNat',
        'insurance', 'registry', 'certDate', 'childReligion', 'childNat',
        'fatherNid', 'fatherReligion', 'motherNid', 'motherReligion',
      };
      expect(kFields.map((f) => f.key).toSet(), expected);
    });
  });

  test('browser OCR output with garbled section headers still fills parents', () {
    const t='''الجسميه :مصر
محل الميلاد :الجيره / بولاق الذكرور
تاريح الميلاد :و امه وضلاتونمنزمايم
عام الف و شسعمانه و سحه و سسعون.
يللب
محمد سعيد فتحى
الديانه؛مسلم 8
الجسميه! مس 86 88 8 م --2
28022222200066
باللا
سارة فتحى محمد
الديناته ؛ مسُلمة 1
29522223200066
الجنميه:مسر 20-66
48
من سنتف :- بولاق الدكر القيم :5057
| من “(مد ان: 8 بيعه نحرّ اول ناء دممبا زه ا 8
نس يه ني ولاق الدكرور لطي .7''';
    final r = CertificateParser.parse(t);
    expect(r.values['fatherName'], 'محمد سعيد فتحى');
    expect(r.values['motherName'], 'سارة فتحى محمد');
    expect(r.values['fatherNid'], '28022222200066');
    expect(r.values['motherNid'], '29522223200066');
    expect(r.values['nid'], isNull);
  });
}
