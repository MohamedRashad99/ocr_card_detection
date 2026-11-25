import 'dart:typed_data';

import 'ocr_engine.dart';

const kImportOcrNotBirthCertificate = 'import_ocr_not_birth_certificate';

const kBirthCertificateLabels = <String>[
  'الاسم',
  'تاريخ الميلاد',
  'محل الميلاد',
  'النوع',
  'الديانة',
  'اسم الأب',
  'اسم الأم',
  'الرقم القومي',
];

class BirthCertificateOcrException implements Exception {
  BirthCertificateOcrException(this.code);

  final String code;

  @override
  String toString() => code;
}

class BirthCertificateReader {
  Future<Map<String, String>> read(Uint8List bytes) async {
    final text = await extractText(bytes, language: 'ara+eng');
    if (!normalizeArabic(text).contains(normalizeArabic('ميلاد'))) {
      throw BirthCertificateOcrException(kImportOcrNotBirthCertificate);
    }
    return extractFields(text, kBirthCertificateLabels);
  }
}

String normalizeArabic(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (_isDiacritic(rune)) continue;
    var folded = _foldAlef(ch);
    if (folded == 'ا') {
      folded = 'ء';
    }
    buffer.write(folded);
  }
  return buffer.toString();
}

Map<String, String> extractFields(String text, List<String> labels) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final result = <String, String>{};
  final normalizedLabels =
      labels.map((label) => normalizeArabic(label)).toList();

  for (final label in labels) {
    result[label] = _valueForLabel(lines, label, normalizedLabels);
  }
  return result;
}

String _valueForLabel(
  List<String> lines,
  String label,
  List<String> normalizedLabels,
) {
  for (var i = 0; i < lines.length; i++) {
    final after = _indexAfterLabel(lines[i], label);
    if (after < 0) continue;
    var value = lines[i].substring(after).trim();
    value = value.replaceFirst(RegExp(r'^[:：\-–]+\s*'), '');
    if (value.isNotEmpty) return value;
    for (var j = i + 1; j < lines.length; j++) {
      if (_isLabelLine(lines[j], normalizedLabels)) continue;
      return lines[j];
    }
    return '';
  }
  return '';
}

bool _isLabelLine(String line, List<String> normalizedLabels) {
  final normalized = normalizeArabic(line);
  for (final label in normalizedLabels) {
    if (normalized.contains(label)) return true;
  }
  return false;
}

int _indexAfterLabel(String line, String label) {
  final nLabel = normalizeArabic(label);
  if (nLabel.isEmpty) return -1;
  for (var start = 0; start < line.length; start++) {
    var i = start;
    var j = 0;
    while (i < line.length && j < nLabel.length) {
      final rune = line.codeUnitAt(i);
      i++;
      if (_isDiacritic(rune)) continue;
      var folded = _foldAlef(String.fromCharCode(rune));
      if (folded == 'ا') folded = 'ء';
      if (folded != nLabel[j]) break;
      j++;
    }
    if (j == nLabel.length) return i;
  }
  return -1;
}

bool _isDiacritic(int rune) {
  return (rune >= 0x064B && rune <= 0x065F) ||
      rune == 0x0670 ||
      (rune >= 0x06D6 && rune <= 0x06ED);
}

String _foldAlef(String ch) {
  switch (ch) {
    case 'أ':
    case 'إ':
    case 'آ':
    case 'ٱ':
    case 'ٵ':
      return 'ا';
    default:
      return ch;
  }
}
