// Single-file Flutter Web app:
//   pick image -> OCR (tesseract.js via flutter_tesseract_ocr) -> parse Arabic
//   birth-certificate text -> fill one TextFormField per field.
//
// The OCR JavaScript hook lives in web/index.html (_extractText).
// All Dart code is kept in this one file on purpose: the parser has no
// Flutter/web dependencies, so it can be unit-tested directly.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OCR شهادة الميلاد',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        // Let the page scroll with mouse wheel, touch AND mouse drag.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
        ),
        home: const OcrFormPage(),
      );
}

// ───────────────────────── Fields ─────────────────────────

class FieldDef {
  const FieldDef(this.key, this.label,
      {this.digits = false, this.optional = false});
  final String key;
  final String label;
  final bool digits;
  final bool optional; // not flagged red when empty
}

const kFields = <FieldDef>[
  FieldDef('serial', 'المسلسل', digits: true),
  FieldDef('issueDate', 'تاريخ الإصدار', digits: true),
  FieldDef('nid', 'الرقم القومي', digits: true),
  FieldDef('name', 'اسم المولود', optional: true),
  FieldDef('gender', 'النوع'),
  FieldDef('birthDate', 'تاريخ الميلاد', digits: true),
  FieldDef('birthPlace', 'محل الميلاد'),
  FieldDef('fatherName', 'اسم الأب'),
  FieldDef('motherName', 'اسم الأم', optional: true),
  FieldDef('fatherNat', 'جنسية الأب'),
  FieldDef('motherNat', 'جنسية الأم'),
  FieldDef('insurance', 'الرقم التأميني', digits: true, optional: true),
  FieldDef('registry', 'جهة القيد', optional: true),
  FieldDef('certDate', 'تاريخ الشهادة', digits: true, optional: true),
];

// ───────────────────────── Parser ─────────────────────────

class NidInfo {
  NidInfo(this.birthDate, this.gender, this.governorate);
  final String birthDate; // dd/MM/yyyy
  final String gender; // ذكر / أنثى
  final String governorate;
}

class ParseResult {
  ParseResult(this.values, this.notes);
  final Map<String, String> values;
  final List<String> notes;
}

enum _Section { child, father, mother }

enum _Kind {
  text,
  date,
  nid,
  number,
  gender,
  name,
  place,
  nationality,
  religion
}

class CertificateParser {
  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  static const _persian = '۰۱۲۳۴۵۶۷۸۹';

  static const _governorates = <String, String>{
    '01': 'القاهرة',
    '02': 'الإسكندرية',
    '03': 'بورسعيد',
    '04': 'السويس',
    '11': 'دمياط',
    '12': 'الدقهلية',
    '13': 'الشرقية',
    '14': 'القليوبية',
    '15': 'كفر الشيخ',
    '16': 'الغربية',
    '17': 'المنوفية',
    '18': 'البحيرة',
    '19': 'الإسماعيلية',
    '21': 'الجيزة',
    '22': 'بني سويف',
    '23': 'الفيوم',
    '24': 'المنيا',
    '25': 'أسيوط',
    '26': 'سوهاج',
    '27': 'قنا',
    '28': 'أسوان',
    '29': 'الأقصر',
    '31': 'البحر الأحمر',
    '32': 'الوادي الجديد',
    '33': 'مطروح',
    '34': 'شمال سيناء',
    '35': 'جنوب سيناء',
    '88': 'خارج الجمهورية',
  };

  // Words that must never be treated as a person's name.
  static const _bannedNameWords = <String>{
    'اسم', 'الاسم', 'بيانات', 'المولود', 'الاب', 'الام', 'الديانه',
    'الجنسيه', 'النوع', 'محل', 'الميلاد', 'تاريخ', 'رقم', 'جهه', 'القيد',
    'المسلسل', 'التاميني', 'الرقم', 'القومي', 'الاصدار', 'الشهاده', 'صوره',
    'قيد', 'جمهوريه', 'مصر', 'العربيه', 'وزاره', 'الداخليه', 'قطاع',
    'الاحوال', 'المدنيه', 'مصلحه', 'المجلس', 'الاعلي', 'وثائق', 'الاسره',
    'المواطنين', 'ذكر', 'انثي', 'انثى', 'مسلم', 'مسلمه', 'مسيحي', 'مسيحيه',
    'يهودي', 'اسلام', 'معالم', 'مصري', 'مصريه', 'بولاق', 'الدكرور',
    'الطبعه', 'طبعه', 'العطيه', 'عام', 'سنه', 'شهر', 'يوم',
    // Spelled-out dates / numbers (OCR often turns a date into words).
    'الف', 'الاف', 'مائه', 'مائة', 'ميه', 'مئه', 'مئتان', 'مائتان',
    'تسعمائه', 'تسعمائة', 'ثمانمائه', 'ثمانمائة', 'سبعمائه', 'سبعمائة',
    'ستمائه', 'ستمائة', 'خمسمائه', 'خمسمائة', 'اربعمائه', 'اربعمائة',
    'ثلاثمائه', 'ثلاثمائة', 'عشرون', 'ثلاثون', 'اربعون', 'خمسون', 'ستون',
    'سبعون', 'ثمانون', 'تسعون', 'واحد', 'واحده', 'اثنان', 'اثنين', 'ثلاثه',
    'اربعه', 'خمسه', 'سته', 'سبعه', 'ثمانيه', 'تسعه', 'عشره', 'احد', 'اول',
    'ثاني', 'ثالث', 'رابع', 'خامس', 'سادس', 'سابع', 'ثامن', 'تاسع', 'عاشر',
    'الاول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع',
    'الثامن', 'التاسع', 'العاشر', 'يناير', 'فبراير', 'مارس', 'ابريل', 'مايو',
    'يونيو', 'يوليو', 'اغسطس', 'سبتمبر', 'اكتوبر', 'نوفمبر', 'ديسمبر',
  };

  /// Arabic/Persian digits → ASCII; strip bidi marks, tatweel, diacritics.
  static String normalize(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i1 = _arabicIndic.indexOf(c);
      final i2 = _persian.indexOf(c);
      if (i1 >= 0) {
        b.write(i1);
      } else if (i2 >= 0) {
        b.write(i2);
      } else {
        b.write(c);
      }
    }
    return b
        .toString()
        .replaceAll(
          RegExp(
              r'[\u200e\u200f\u202a-\u202e\u2066-\u2069\u064b-\u065f\u0640]'),
          '',
        )
        .replaceAll('\r', '');
  }

  // 1:1 replacements only, so indexes stay aligned with the original line.
  static String fold(String s) => s
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');

  static String digitsOf(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Keep only Arabic letters, spaces and dashes; drop 1-letter OCR noise.
  static String arabicOnly(String s) {
    var t = s.replaceAll(RegExp(r'[^\u0600-\u06FF\s\-–—]'), ' ');
    t = t.replaceAll(RegExp(r'[\u060C\u061B\u061F\u066A-\u066D\u06D4]'), ' ');
    final dash = RegExp(r'^[-–—]+$');
    final kept = t
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && (w.length > 1 || dash.hasMatch(w)))
        .map((w) => dash.hasMatch(w) ? '-' : w);
    return kept.join(' ').replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '');
  }

  static int _min3(int a, int b, int c) {
    var m = a < b ? a : b;
    return m < c ? m : c;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        cur[j + 1] = _min3(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = cur[j];
      }
    }
    return prev[b.length];
  }

  /// OCR-tolerant word compare. Short labels must keep their length (one
  /// edit only), longer labels allow 2-3 edits.
  static bool _fuzzy(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    if (b.length <= 5) {
      return a.length == b.length && _levenshtein(a, b) <= 1;
    }
    final max = b.length <= 7 ? 2 : 3;
    if ((a.length - b.length).abs() > max) return false;
    return _levenshtein(a, b) <= max;
  }

  static String _normWord(String s) => fold(normalize(s));

  static String? _matchGovernorate(String word) {
    final w = fold(word);
    String? best;
    var bestDistance = 1 << 30;
    for (final g in _governorates.values) {
      final fg = fold(g);
      final max = fg.length <= 5 ? 1 : (fg.length <= 7 ? 2 : 3);
      if ((w.length - fg.length).abs() > max) continue;
      final d = _levenshtein(w, fg);
      if (d <= max && d < bestDistance) {
        bestDistance = d;
        best = g;
      }
    }
    return best;
  }

  static bool _isGovernorate(String word) => _matchGovernorate(word) != null;

  static String _fixGovernorate(String word) => _matchGovernorate(word) ?? word;

  // ── dates ──

  static String? _fmt(int y, int m, int d) {
    if (y < 1900 || y > DateTime.now().year + 1) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return null;
    return '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
  }

  static int _yearOf(int value) => value > 9999
      ? int.tryParse(value.toString().substring(0, 4)) ?? value
      : value;

  static int _dayOf(int value) => value > 31
      ? int.tryParse(value.toString().substring(0, 2)) ?? value
      : value;

  static List<String> _datesInText(String s) {
    final out = <String>[];
    final re = RegExp(r'(\d{1,5})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,5})');
    for (final m in re.allMatches(s)) {
      final a = int.tryParse(m[1]!);
      final b = int.tryParse(m[2]!);
      final c = int.tryParse(m[3]!);
      if (a == null || b == null || c == null) continue;

      // OCR sometimes glues an extra digit to the year or the day, e.g.
      // 20202/08/258 instead of 2020/08/25.
      final candidates = <String?>[
        if (a > 31) _fmt(_yearOf(a), b, _dayOf(c)),
        if (c > 31) _fmt(_yearOf(c), b, _dayOf(a)),
        if (m[1]!.length >= 5)
          _fmt(_yearOf(int.parse(m[1]!.substring(0, 4))), b, _dayOf(c)),
        if (m[3]!.length >= 3)
          _fmt(_yearOf(a), b, _dayOf(int.parse(m[3]!.substring(0, 2)))),
      ];
      for (final date in candidates) {
        if (date != null && !out.contains(date)) {
          out.add(date);
          break;
        }
      }
    }
    return out;
  }

  static String? _dateFromText(String s) {
    final dates = _datesInText(s);
    return dates.isEmpty ? null : dates.first;
  }

  static int _dateKey(String d) {
    final p = d.split('/');
    if (p.length != 3) return 0;
    final y = int.tryParse(p[2]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final day = int.tryParse(p[0]) ?? 0;
    return y * 10000 + m * 100 + day;
  }

  // ── national ID ──

  static bool _looksLikeNid(String id) => RegExp(r'^[23]\d{13}$').hasMatch(id);

  static NidInfo? decodeNid(String id) {
    if (!_looksLikeNid(id)) return null;
    final century = id[0] == '2' ? 1900 : 2000;
    final y = century + int.parse(id.substring(1, 3));
    if (y > DateTime.now().year) return null;
    final date =
        _fmt(y, int.parse(id.substring(3, 5)), int.parse(id.substring(5, 7)));
    final gov = _governorates[id.substring(7, 9)];
    if (date == null || gov == null) return null;
    final male = int.parse(id[12]).isOdd;
    return NidInfo(date, male ? 'ذكر' : 'أنثى', gov);
  }

  // ── token / label matching ──

  static List<_Token> _tokens(String line) {
    final out = <_Token>[];
    final re = RegExp(r'[^\s:：؛;\-–—|]+');
    for (final m in re.allMatches(line)) {
      final raw = m[0]!;
      out.add(_Token(raw, _normWord(raw), m.start, m.end));
    }
    return out;
  }

  static final _rules = <_LabelRule>[
    const _LabelRule('fatherNat', ['جنسيه', 'الاب'], _Kind.nationality),
    const _LabelRule('motherNat', ['جنسيه', 'الام'], _Kind.nationality),
    const _LabelRule('fatherName', ['اسم', 'الاب'], _Kind.name),
    const _LabelRule('motherName', ['اسم', 'الام'], _Kind.name),
    const _LabelRule('name', ['اسم', 'المولود'], _Kind.name),
    const _LabelRule('name', ['الاسم'], _Kind.name),
    const _LabelRule('birthPlace', ['محل', 'الميلاد'], _Kind.place),
    const _LabelRule('birthPlace', ['محل'], _Kind.place),
    const _LabelRule('birthDate', ['تاريخ', 'الميلاد'], _Kind.date),
    const _LabelRule('birthDate', ['الميلاد'], _Kind.date),
    const _LabelRule('issueDate', ['تاريخ', 'الاصدار'], _Kind.date),
    const _LabelRule('issueDate', ['الاصدار'], _Kind.date),
    const _LabelRule('certDate', ['تاريخ', 'الشهاده'], _Kind.date),
    const _LabelRule('insurance', ['الرقم', 'التاميني'], _Kind.number),
    const _LabelRule('insurance', ['التاميني'], _Kind.number),
    const _LabelRule('nid', ['الرقم', 'القومي'], _Kind.nid),
    const _LabelRule('nid', ['القومي'], _Kind.nid),
    const _LabelRule('serial', ['رقم', 'القيد'], _Kind.number),
    const _LabelRule('serial', ['المسلسل'], _Kind.number),
    const _LabelRule('registry', ['جهه', 'القيد'], _Kind.place),
    const _LabelRule('gender', ['النوع'], _Kind.gender),
    const _LabelRule('gender', ['الحوع'], _Kind.gender),
    const _LabelRule('gender', ['لحوع'], _Kind.gender),
    const _LabelRule('religion', ['الديانه'], _Kind.religion),
    const _LabelRule('nationality', ['الجنسيه'], _Kind.nationality),
  ];

  static List<_LabelMatch> _findLabels(List<_Token> tokens) {
    final matches = <_LabelMatch>[];
    for (final rule in _rules) {
      for (var i = 0; i + rule.words.length <= tokens.length; i++) {
        var ok = true;
        for (var j = 0; j < rule.words.length; j++) {
          final token = tokens[i + j].norm;
          final word = rule.words[j];
          // "الأب" and "الأم" differ by a single letter; never fuzzy-match
          // one as the other.
          if ((word == 'الاب' || word == 'الام') && token != word) {
            ok = false;
            break;
          }
          if (!_fuzzy(token, word)) {
            ok = false;
            break;
          }
        }
        if (ok) {
          matches.add(_LabelMatch(
            rule.key,
            rule.kind,
            tokens[i].start,
            tokens[i + rule.words.length - 1].end,
            rule.words.length,
          ));
        }
      }
    }
    matches.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return b.length.compareTo(a.length);
    });
    final kept = <_LabelMatch>[];
    for (final m in matches) {
      if (kept.any((k) => m.start < k.end && m.end > k.start)) continue;
      kept.add(m);
    }
    kept.sort((a, b) => a.start.compareTo(b.start));
    return kept;
  }

  static bool _near(String a, String b, int max) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > max) return false;
    return _levenshtein(a, b) <= max;
  }

  /// Detects "بيانات المولود" / "بيانات الأب" / "بيانات الأم" headers,
  /// including the badly mangled versions produced by OCR.
  static _SectionMatch? _findSection(String line, List<_Token> tokens) {
    if (tokens.isEmpty) return null;
    final norms = tokens.map((t) => t.norm).toList();
    final hasColon = line.contains(':') || line.contains('：');
    final flat = norms.join();

    // "بيانات" followed by the person's section word.
    for (var i = 0; i < norms.length; i++) {
      if (!_near(norms[i], 'بيانات', 2)) continue;
      for (var j = i + 1; j < norms.length; j++) {
        if (_near(norms[j], 'المولود', 1)) {
          return _SectionMatch(
            _Section.child,
            tokens[i].start,
            tokens[j].end,
            2,
          );
        }
        if (norms[j] == 'الاب') {
          return _SectionMatch(
            _Section.father,
            tokens[i].start,
            tokens[j].end,
            2,
          );
        }
        if (norms[j] == 'الام') {
          return _SectionMatch(
            _Section.mother,
            tokens[i].start,
            tokens[j].end,
            2,
          );
        }
      }
    }

    // Lines that are only a section word, e.g. a standalone "بيانات الأب"
    // that OCR split across lines.
    if (!hasColon && tokens.length <= 3) {
      for (var i = 0; i < norms.length; i++) {
        if (_near(norms[i], 'المولود', 1)) {
          return _SectionMatch(
            _Section.child,
            tokens[i].start,
            tokens[i].end,
            1,
          );
        }
        if (norms[i] == 'الاب') {
          return _SectionMatch(
            _Section.father,
            tokens[i].start,
            tokens[i].end,
            1,
          );
        }
        if (norms[i] == 'الام') {
          return _SectionMatch(
            _Section.mother,
            tokens[i].start,
            tokens[i].end,
            1,
          );
        }
      }
    }

    if (hasColon) return null;

    // "بياباملاب" (بيانات الأب) and "بميان م الامر" (بيانات الأم).
    if (tokens.length <= 2 && flat.startsWith('بيا') && flat.endsWith('لاب')) {
      return _SectionMatch(
        _Section.father,
        tokens.first.start,
        tokens.last.end,
        1,
      );
    }
    if (tokens.length <= 4 && flat.contains('بميا') && flat.contains('الام')) {
      return _SectionMatch(
        _Section.mother,
        tokens.first.start,
        tokens.last.end,
        1,
      );
    }
    return null;
  }

  // ── value cleaning / scoring ──

  static String _cleanValue(String s) {
    var t = s.trim();
    t = t.replaceFirst(RegExp(r'^[\s:：؛;\-–—|]+'), '');
    t = t.replaceFirst(RegExp(r'[\s:：؛;\-–—|]+$'), '');
    return t.trim();
  }

  static String? _cleanName(String s) {
    final t = arabicOnly(s);
    if (t.isEmpty) return null;
    final words = t.split(RegExp(r'\s+'));
    if (words.length > 5) return null;
    for (final w in words) {
      final f = fold(w);
      if (f.length < 2) return null;
      if (_bannedNameWords.contains(f)) return null;
      if (_isGovernorate(f)) return null;
    }
    return words.join(' ');
  }

  static bool _isPlaceLike(String s) {
    final t = arabicOnly(s);
    if (t.isEmpty) return false;
    final words = t.split(RegExp(r'\s+'));
    if (words.any((w) => _isGovernorate(fold(w)))) return true;
    if (words.length >= 2) return true;
    return false;
  }

  static String? _cleanPlace(String s) {
    final t = s.trim();
    final parts = t
        .split(RegExp(r'\s*[/\-–—|]\s*'))
        .map(arabicOnly)
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return parts.map(_fixGovernorate).join(' - ');
    }
    final single = arabicOnly(t);
    if (single.isEmpty) return null;
    final words = single.split(RegExp(r'\s+'));
    if (words.length >= 2 && _isGovernorate(fold(words.first))) {
      return '${_fixGovernorate(words.first)} - ${words.skip(1).join(' ')}';
    }
    return _fixGovernorate(single);
  }

  // Common nationalities on Egyptian certificates. Anything else is treated
  // as OCR noise instead of being written into the nationality fields.
  static const _knownNationalities = <String>[
    'مصر', 'السودان', 'ليبيا', 'تونس', 'الجزائر', 'المغرب', 'الأردن', 'لبنان',
    'سوريا', 'العراق', 'فلسطين', 'اليمن', 'السعودية', 'الكويت', 'الإمارات',
    'قطر', 'البحرين', 'عمان', 'الصومال', 'جيبوتي', 'موريتانيا', 'تركيا',
    'أمريكا', 'بريطانيا', 'فرنسا', 'ألمانيا', 'إيطاليا', 'اليونان', 'قبرص',
    'الهند', 'باكستان', 'الفلبين', 'إندونيسيا', 'نيجيريا', 'إثيوبيا',
    'إريتريا', 'تشاد', 'كندا', 'أستراليا',
  ];

  static String? _cleanNationality(String s) {
    final t = arabicOnly(s);
    if (t.isEmpty) return null;
    final f = fold(t);
    if (f.contains('مصر') || _fuzzy(f, 'مصر') || _fuzzy(f, 'مصري')) {
      return 'مصر';
    }
    for (final n in _knownNationalities) {
      final fn = fold(n);
      if (f == fn || f.contains(fn)) return n;
    }
    return null;
  }

  static String? _normalizeGender(String s) {
    final f = fold(arabicOnly(s));
    if (f.contains('ذكر') || f.contains('4كر') || f.contains('كر')) return 'ذكر';
    if (f.contains('انث') || f.contains('انتي')) return 'أنثى';
    return null;
  }

  /// True = female wording (مسلمة / مسيحية), false = male, null = unknown.
  static bool? _religionIsFemale(String s) {
    final f = fold(arabicOnly(s));
    if (f.contains('مسلمه') ||
        f.contains('مسيحيه') ||
        f.contains('يهوديه')) {
      return true;
    }
    if (f.contains('مسلم') ||
        f.contains('مسيحي') ||
        f.contains('يهودي') ||
        f.contains('اسلام')) {
      return false;
    }
    return null;
  }

  static String? _cleanReligion(String s) {
    final f = fold(arabicOnly(s));
    if (f.contains('مسل') || f.contains('اسلام') || f.contains('معالم')) {
      return 'مسلم';
    }
    if (f.contains('مسيح')) return 'مسيحي';
    if (f.contains('يهود')) return 'يهودي';
    return null;
  }

  static int _scoreForKind(String value, _Kind kind) {
    if (value.isEmpty) return 0;
    switch (kind) {
      case _Kind.date:
        return _dateFromText(value) != null ? 20 : 0;
      case _Kind.nid:
        final d = digitsOf(value);
        if (d.length >= 14 && decodeNid(d.substring(0, 14)) != null) return 20;
        return d.length >= 14 ? 10 : 0;
      case _Kind.number:
        return digitsOf(value).isNotEmpty ? 10 : 0;
      case _Kind.gender:
        return _normalizeGender(value) != null ? 10 : 0;
      case _Kind.name:
        return _cleanName(value) != null ? 10 : 0;
      case _Kind.place:
        return _isPlaceLike(value) ? 10 : 0;
      case _Kind.nationality:
        return _cleanNationality(value) != null ? 10 : 0;
      case _Kind.religion:
        return _cleanReligion(value) != null ? 10 : 0;
      case _Kind.text:
        return 1;
    }
  }

  static String? _cleanForKind(String value, _Kind kind) {
    switch (kind) {
      case _Kind.date:
        return _dateFromText(value);
      case _Kind.nid:
        final d = digitsOf(value);
        if (d.length >= 14) {
          final c = d.substring(0, 14);
          if (_looksLikeNid(c)) return c;
        }
        return null;
      case _Kind.number:
        final d = digitsOf(value);
        return d.isEmpty ? null : d;
      case _Kind.gender:
        return _normalizeGender(value);
      case _Kind.name:
        return _cleanName(value);
      case _Kind.place:
        return _cleanPlace(value);
      case _Kind.nationality:
        return _cleanNationality(value);
      case _Kind.religion:
        return _cleanReligion(value);
      case _Kind.text:
        final t = arabicOnly(value);
        return t.isEmpty ? null : t;
    }
  }

  static String? _chooseValue(String after, String before, _Kind kind) {
    final a = _scoreForKind(after, kind);
    final b = _scoreForKind(before, kind);
    if (a > 0 || b > 0) return a >= b ? after : before;
    if (after.isNotEmpty) return after;
    if (before.isNotEmpty) return before;
    return null;
  }

  // ── candidates ──

  static List<_NameCandidate> _nameCandidates(List<_LineInfo> infos) {
    final out = <_NameCandidate>[];
    final childHeader = infos.indexWhere(
      (l) => l.sectionMatch?.section == _Section.child,
    );
    final start = childHeader >= 0 ? childHeader : 0;
    for (var i = start; i < infos.length; i++) {
      final line = infos[i];
      if (line.sectionMatch != null) {
        final extra = _extraAfterHeader(line);
        if (extra != null) {
          out.add(_NameCandidate(extra, i, 10));
        }
        continue;
      }
      if (line.labels.isNotEmpty) continue;
      final name = _cleanName(line.text);
      if (name != null) {
        final n = name.split(RegExp(r'\s+')).length;
        final score = n >= 2 && n <= 4 ? 10 : (n == 1 ? 5 : 1);
        out.add(_NameCandidate(name, i, score));
      }
    }
    return out;
  }

  static String? _extraAfterHeader(_LineInfo line) {
    final m = line.sectionMatch;
    if (m == null || m.wordCount < 2) return null;
    return _cleanName(line.text.substring(m.end));
  }

  /// The name usually sits on the line directly below a "بيانات الأب/الأم"
  /// header, before the first labelled field. Reading it by position is much
  /// more reliable than guessing from all name-like lines in the document.
  static String? _nameNearSection(List<_LineInfo> infos, _Section section) {
    final idx = infos.indexWhere((l) => l.sectionMatch?.section == section);
    if (idx < 0) return null;
    final extra = _extraAfterHeader(infos[idx]);
    if (extra != null) return extra;
    for (var i = idx + 1; i < infos.length && i <= idx + 4; i++) {
      final line = infos[i];
      if (line.sectionMatch != null) break;
      if (line.labels.isNotEmpty) break;
      final name = _cleanName(line.text);
      if (name != null) return name;
    }
    return null;
  }

  static List<_NidCandidate> _nidCandidates(List<_LineInfo> infos) {
    final out = <_NidCandidate>[];
    final seen = <String>{};
    for (final line in infos) {
      final digits = digitsOf(line.text);
      for (var i = 0; i + 14 <= digits.length; i++) {
        final raw = digits.substring(i, i + 14);
        if (!_looksLikeNid(raw)) continue;
        final info = decodeNid(raw);
        if (!seen.add('${line.index}:$raw')) continue;
        out.add(_NidCandidate(raw, info, line.index));
      }
    }
    return out;
  }

  // ── main parser ──

  static ParseResult parse(String rawText) {
    final text = normalize(rawText);
    final lines = text
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final infos = <_LineInfo>[];
    for (var i = 0; i < lines.length; i++) {
      final tokens = _tokens(lines[i]);
      final labels = _findLabels(tokens);
      final sectionMatch = _findSection(lines[i], tokens);
      infos.add(_LineInfo(i, lines[i], tokens, labels, sectionMatch));
    }

    final childIdx =
        infos.indexWhere((l) => l.sectionMatch?.section == _Section.child);
    final fatherIdx =
        infos.indexWhere((l) => l.sectionMatch?.section == _Section.father);
    final motherIdx =
        infos.indexWhere((l) => l.sectionMatch?.section == _Section.mother);

    final names = _nameCandidates(infos);
    final nids = _nidCandidates(infos);

    // Last line that holds a child-specific field (gender/place/date).
    int? childFieldEnd;
    for (final line in infos) {
      if (motherIdx >= 0 && line.index >= motherIdx) break;
      if (line.labels.any((m) =>
          m.key == 'gender' || m.key == 'birthPlace' || m.key == 'birthDate')) {
        childFieldEnd = line.index;
      }
    }

    // Find where the father's block starts. The father header is often the
    // line that OCR mangles most, so fall back to the first name/NID after
    // the child's fields.
    int? fatherStart;
    if (fatherIdx >= 0) {
      fatherStart = fatherIdx;
    } else {
      var from = childFieldEnd ?? childIdx;
      if (from < 0) from = 0;
      final candidates = <int>[
        for (final n in names)
          if (n.line >= from && (motherIdx < 0 || n.line < motherIdx)) n.line,
        for (final n in nids)
          if (n.line >= from && (motherIdx < 0 || n.line < motherIdx)) n.line,
      ]..sort();
      if (candidates.isNotEmpty) {
        fatherStart = candidates.first;
      } else if (motherIdx >= 0) {
        fatherStart = motherIdx;
      }
    }

    int? motherStart = motherIdx >= 0 ? motherIdx : null;
    if (motherStart == null && fatherStart != null) {
      final after = names.where((n) => n.line > fatherStart!).toList();
      if (after.isNotEmpty) motherStart = after.first.line;
    }

    for (final line in infos) {
      final i = line.index;
      if (childIdx >= 0 &&
          i >= childIdx &&
          (fatherStart == null || i < fatherStart)) {
        line.section = _Section.child;
      } else if (fatherStart != null &&
          i >= fatherStart &&
          (motherStart == null || i < motherStart)) {
        line.section = _Section.father;
      } else if (motherStart != null && i >= motherStart) {
        line.section = _Section.mother;
      } else {
        line.section = null;
      }
    }

    // Collect label -> value pairs, keeping the section they came from.
    final raw = <String, List<_Value>>{};
    for (final line in infos) {
      // Section headers are not label/value lines.
      if (line.sectionMatch != null) continue;
      final labels = line.labels;
      for (var j = 0; j < labels.length; j++) {
        final m = labels[j];
        final prevEnd = j > 0 ? labels[j - 1].end : 0;
        final nextStart =
            j + 1 < labels.length ? labels[j + 1].start : line.text.length;
        final after = _cleanValue(line.text.substring(m.end, nextStart));
        final before = _cleanValue(line.text.substring(prevEnd, m.start));
        final chosen = _chooseValue(after, before, m.kind);
        if (chosen == null) continue;
        final cleaned = _cleanForKind(chosen, m.kind);
        if (cleaned == null) continue;
        raw.putIfAbsent(m.key, () => []).add(
              _Value(
                cleaned,
                line.index,
                line.section,
                _scoreForKind(cleaned, m.kind),
              ),
            );
      }
    }

    final out = <String, String>{};
    final notes = <String>[];

    _Value? bestValue(String key, {_Section? section, bool fallback = true}) {
      final list = raw[key];
      if (list == null || list.isEmpty) return null;
      final scoped = section == null
          ? list
          : list.where((v) => v.section == section).toList();
      final pool =
          scoped.isNotEmpty ? scoped : (fallback ? list : const <_Value>[]);
      if (pool.isEmpty) return null;
      final sorted = List<_Value>.of(pool)
        ..sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : a.line.compareTo(b.line);
        });
      return sorted.first;
    }

    String? pickValue(String key, {_Section? section, bool fallback = true}) =>
        bestValue(key, section: section, fallback: fallback)?.value;

    final hasChildSection = childIdx >= 0;
    final hasFatherSection = fatherIdx >= 0;
    final hasMotherSection = motherIdx >= 0;

    final fatherName = _nameNearSection(infos, _Section.father) ??
        pickValue('fatherName',
            section: _Section.father, fallback: !hasFatherSection);
    final motherName = _nameNearSection(infos, _Section.mother) ??
        pickValue('motherName',
            section: _Section.mother, fallback: !hasMotherSection);
    final childName = _nameNearSection(infos, _Section.child) ??
        pickValue('name', section: _Section.child, fallback: !hasChildSection);

    final genderValue = pickValue('gender',
        section: _Section.child, fallback: !hasChildSection);

    // National ID: prefer a value that belongs to the child's own block.
    String? nid;
    _Section? nidSection;
    final labeledNid =
        bestValue('nid', section: _Section.child, fallback: !hasChildSection);
    if (labeledNid != null) {
      nid = labeledNid.value;
      nidSection = labeledNid.section;
    } else {
      final childNids =
          nids.where((n) => infos[n.line].section == _Section.child).toList();
      final chosen = childNids.isNotEmpty
          ? childNids.first
          : (nids.isNotEmpty ? nids.first : null);
      if (chosen != null) {
        nid = chosen.id;
        nidSection = infos[chosen.line].section;
        if (nidSection != _Section.child) {
          notes.add(
            'لم يُعثر على الرقم القومي للمولود، فتم استخدام أول رقم قومي صالح في الشهادة. راجع الحقل يدويًا.',
          );
        }
      }
    }

    // Only trust NID-derived data when the NID is inside the child's block.
    final childNid =
        nidSection == _Section.child && nid != null ? decodeNid(nid) : null;

    final birthDate = pickValue('birthDate',
            section: _Section.child, fallback: !hasChildSection) ??
        childNid?.birthDate;
    final gender = genderValue ?? childNid?.gender;
    final birthPlace = pickValue('birthPlace',
            section: _Section.child, fallback: !hasChildSection) ??
        childNid?.governorate;

    final fatherNat = pickValue('fatherNat',
            section: _Section.father, fallback: !hasFatherSection) ??
        pickValue('nationality',
            section: _Section.father, fallback: !hasFatherSection);
    final motherNat = pickValue('motherNat',
            section: _Section.mother, fallback: !hasMotherSection) ??
        pickValue('nationality',
            section: _Section.mother, fallback: !hasMotherSection);

    final serial = pickValue('serial');
    final insurance = pickValue('insurance');
    var registry = pickValue('registry',
            section: _Section.child, fallback: !hasChildSection) ??
        pickValue('registry');
    if (registry == null && birthPlace != null && birthPlace.contains(' - ')) {
      registry = birthPlace.split(' - ').last.trim();
    }

    var issueDate = pickValue('issueDate');
    final certDate = pickValue('certDate');

    if (issueDate == null) {
      final dates = <String>[];
      for (final line in infos) {
        if (line.labels.any((m) => m.key == 'birthDate')) continue;
        dates.addAll(_datesInText(line.text));
      }
      if (dates.isNotEmpty) {
        dates.sort((a, b) => _dateKey(b).compareTo(_dateKey(a)));
        issueDate = dates.first;
        notes.add(
          'تاريخ الإصدار غير مذكور بوضوح، فتم استخدام أحدث تاريخ في الشهادة.',
        );
      }
    }

    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) out[key] = v;
    }

    put('serial', serial);
    put('issueDate', issueDate);
    put('nid', nid);
    put('name', childName);
    put('gender', gender);
    put('birthDate', birthDate);
    put('birthPlace', birthPlace);
    put('fatherName', fatherName);
    put('motherName', motherName);
    put('fatherNat', fatherNat);
    put('motherNat', motherNat);
    put('insurance', insurance);
    put('registry', registry);
    put('certDate', certDate);

    final foldedText = fold(text);
    if (!foldedText.contains('ميلاد') &&
        !foldedText.contains('مولود') &&
        !foldedText.contains('قومي') &&
        !foldedText.contains('قيد')) {
      notes.insert(0, 'النص المستخرج لا يبدو شهادة ميلاد. جرّب صورة أوضح.');
    }

    for (final f in kFields) {
      if (f.optional) continue;
      if ((out[f.key] ?? '').isEmpty) {
        notes.add('لم يتم التعرف على «${f.label}». أدخله يدويًا.');
      }
    }

    return ParseResult(out, notes);
  }
}

// ───────────────────────── Parser helpers ─────────────────────────

class _Token {
  const _Token(this.raw, this.norm, this.start, this.end);
  final String raw;
  final String norm;
  final int start;
  final int end;
}

class _LabelRule {
  const _LabelRule(this.key, this.words, this.kind);
  final String key;
  final List<String> words;
  final _Kind kind;
}

class _LabelMatch {
  const _LabelMatch(this.key, this.kind, this.start, this.end, this.length);
  final String key;
  final _Kind kind;
  final int start;
  final int end;
  final int length;
}

class _SectionMatch {
  const _SectionMatch(this.section, this.start, this.end, this.wordCount);
  final _Section section;
  final int start;
  final int end;
  final int wordCount;
}

class _LineInfo {
  _LineInfo(this.index, this.text, this.tokens, this.labels, this.sectionMatch);
  final int index;
  final String text;
  final List<_Token> tokens;
  final List<_LabelMatch> labels;
  final _SectionMatch? sectionMatch;
  _Section? section;
}

class _Value {
  const _Value(this.value, this.line, this.section, this.score);
  final String value;
  final int line;
  final _Section? section;
  final int score;
}

class _NameCandidate {
  const _NameCandidate(this.name, this.line, this.score);
  final String name;
  final int line;
  final int score;
}

class _NidCandidate {
  const _NidCandidate(this.id, this.info, this.line);
  final String id;
  final NidInfo? info;
  final int line;
}

// ───────────────────────── UI ─────────────────────────

class OcrFormPage extends StatefulWidget {
  const OcrFormPage({super.key});

  @override
  State<OcrFormPage> createState() => _OcrFormPageState();
}

class _OcrFormPageState extends State<OcrFormPage> {
  final Map<String, TextEditingController> _controllers = {
    for (final f in kFields) f.key: TextEditingController(),
  };

  bool _busy = false;
  String? _error;
  String? _status;
  List<String> _notes = const [];
  String _rawText = '';
  String? _imageName;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAndRead() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _notes = const [];
      _rawText = '';
      _imageName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('الملف فارغ.');

      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : lower.endsWith('.bmp')
                  ? 'image/bmp'
                  : 'image/jpeg';
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

      final text = await FlutterTesseractOcr.extractText(
        dataUrl,
        language: 'ara+eng',
        args: {
          'preserve_interword_spaces': '1',
          'user_defined_dpi': '300',
        },
      );

      if (text.trim().startsWith('__OCR_ERROR__')) {
        throw Exception(text.trim());
      }
      if (text.trim().isEmpty) {
        throw Exception(
          'تعذر استخراج نص من الصورة. جرّب صورة أوضح أو إضاءة أفضل.',
        );
      }

      final parsed = CertificateParser.parse(text);
      if (!mounted) return;
      setState(() {
        _imageName = file.name;
        _rawText = text;
        _notes = parsed.notes;
        _status = parsed.values.isEmpty
            ? 'لم يتم التعرف على بيانات. راجع النص المستخرج.'
            : 'تم استخراج البيانات. راجعها قبل الحفظ.';
        for (final f in kFields) {
          _controllers[f.key]!.text = parsed.values[f.key] ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {
      _notes = const [];
      _rawText = '';
      _status = null;
      _error = null;
      _imageName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('قراءة شهادة الميلاد (OCR)'),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'ارفع صورة شهادة الميلاد المصرية، وسيتم استخراج البيانات تلقائيًا.',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'للحصول على أفضل نتيجة: صورة واضحة، مضيئة، وغير مائلة.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _busy ? null : _pickAndRead,
                                  icon: const Icon(Icons.upload_file),
                                  label: Text(
                                    _busy
                                        ? 'جارٍ قراءة الصورة…'
                                        : 'اختر صورة الشهادة',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _clear,
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('مسح الحقول'),
                                ),
                              ],
                            ),
                            if (_busy) ...[
                              const SizedBox(height: 16),
                              const LinearProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(
                                'يتم تشغيل OCR على الصورة… قد يستغرق ذلك بعض الوقت.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (_imageName != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'الصورة: $_imageName',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (_status != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _status!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _MessageBox(
                        icon: Icons.error_outline,
                        color: theme.colorScheme.errorContainer,
                        textColor: theme.colorScheme.onErrorContainer,
                        title: 'تعذر قراءة الشهادة',
                        lines: [_error!],
                      ),
                    ],
                    if (_notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _MessageBox(
                        icon: Icons.info_outline,
                        color: theme.colorScheme.secondaryContainer,
                        textColor: theme.colorScheme.onSecondaryContainer,
                        title: 'ملاحظات',
                        lines: _notes,
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 720 ? 2 : 1;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: kFields.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 84,
                          ),
                          itemBuilder: (context, index) {
                            final field = kFields[index];
                            return TextField(
                              controller: _controllers[field.key],
                              textDirection: TextDirection.rtl,
                              keyboardType: field.digits
                                  ? TextInputType.number
                                  : TextInputType.text,
                              inputFormatters: field.digits
                                  ? [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9٠-٩/.\-]'),
                                      ),
                                    ]
                                  : null,
                              decoration: InputDecoration(
                                labelText: field.label,
                                border: const OutlineInputBorder(),
                                prefixIcon: Icon(
                                  field.optional
                                      ? Icons.edit_note
                                      : Icons.check_circle_outline,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (_rawText.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: ExpansionTile(
                          title: const Text('النص المستخرج من الصورة (OCR)'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                _rawText,
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.icon,
    required this.color,
    required this.textColor,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color color;
  final Color textColor;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $line',
                style: TextStyle(color: textColor),
              ),
            ),
        ],
      ),
    );
  }
}
