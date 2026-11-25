// Layout-aware reading of an Egyptian birth certificate.
//
// The browser OCR (web/ocr_pipeline.js) returns every text segment with its
// position. Here we use the fixed layout of the form (child, father, mother
// blocks, each with religion / nationality labels and a name above them) to
// assign segments to fields, and fuzzy-match the garbled Arabic labels.
// Pure Dart: no Flutter or web imports, so it is unit-testable.

import 'dart:convert';

class OcrSeg {
  OcrSeg(this.text, this.conf, this.row, this.top, this.bottom, this.left,
      this.right, this.digits);
  final String text;
  final int conf;
  final int row;
  final int top;
  final int bottom;
  final int left;
  final int right;
  final bool digits;
}

/// Returns the segments if [raw] is the JSON produced by the pipeline.
List<OcrSeg>? decodeSegments(String raw) {
  final t = raw.trim();
  if (!t.startsWith('{')) return null;
  try {
    final j = jsonDecode(t) as Map<String, dynamic>;
    final list = (j['segs'] as List).cast<Map<String, dynamic>>();
    return [
      for (final s in list)
        OcrSeg(
          (s['t'] ?? '') as String,
          ((s['conf'] ?? 0) as num).toInt(),
          ((s['row'] ?? 0) as num).toInt(),
          ((s['top'] ?? 0) as num).toInt(),
          ((s['bottom'] ?? 0) as num).toInt(),
          ((s['left'] ?? 0) as num).toInt(),
          ((s['right'] ?? 0) as num).toInt(),
          (s['digits'] ?? false) as bool,
        ),
    ];
  } catch (_) {
    return null;
  }
}

String segmentsToText(List<OcrSeg> segs) => segs.map((s) => s.text).join('\n');

// ───────── text helpers ─────────

String _norm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640) continue;
    if (r == 0x200F || r == 0x200E || r == 0x202B || r == 0x202C) continue;
    switch (r) {
      case 0x0623:
      case 0x0625:
      case 0x0622:
      case 0x0671:
        b.writeCharCode(0x0627);
      case 0x0649:
        b.writeCharCode(0x064A);
      case 0x0629:
        b.writeCharCode(0x0647);
      default:
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

String _arabicOnly(String s) =>
    _norm(s).replaceAll(RegExp(r'[^\u0621-\u064A]'), '');

int _lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

bool _close(String a, String label, [int? maxDist]) {
  final d = maxDist ?? (label.length * 0.43).floor().clamp(1, 4);
  return _lev(a, label) <= d;
}

final _colon = RegExp(r'[:：؛;!]');

class _Lbl {
  _Lbl(this.kind, this.value);
  final String kind; // religion nat gender place date or ''
  final String value;
}

const _labels = {
  'religion': 'الديانه',
  'nat': 'الجنسيه',
  'gender': 'النوع',
  'place': 'محلالميلاد',
  'date': 'تاريخالميلاد',
};

_Lbl _classify(String text) {
  final t = text.replaceAll(RegExp(r'[|\[\]()<>“”"«»]'), ' ').trim();
  final m = _colon.firstMatch(t);
  String head = t;
  String value = '';
  if (m != null && m.start > 1) {
    head = t.substring(0, m.start);
    value = t.substring(m.end);
  }
  // Without a colon, the label may still be the first word(s).
  String h = _arabicOnly(head);
  String? found;
  for (final e in _labels.entries) {
    if (h.isNotEmpty && _close(h, e.value)) {
      found = e.key;
      break;
    }
  }
  if (found == null && m == null) {
    // label glued to a dot: "الجوع.وكر"
    final dot = RegExp(r'[.,]').firstMatch(t);
    if (dot != null && dot.start > 2) {
      final h2 = _arabicOnly(t.substring(0, dot.start));
      for (final e in _labels.entries) {
        if (h2.isNotEmpty && _close(h2, e.value)) {
          return _Lbl(e.key, t.substring(dot.end));
        }
      }
    }
  }
  if (found == null && m != null && m.start > 1) {
    // garbled label: use its first letters, or a religion-looking value
    if (h.startsWith('الدي') || h.startsWith('الد') && h.length >= 6) {
      found = 'religion';
    } else if (RegExp(r'^ال[جح][نمسص]').hasMatch(h) && h.length <= 9) {
      found = 'nat';
    } else if (_religion(value, female: false) != null &&
        _arabicOnly(value).length >= 4 && h.length >= 4) {
      found = 'religion';
    }
  }
  if (found != null) return _Lbl(found, value);
  return _Lbl('', t);
}

String _cleanValue(String s) => s
    .replaceAll(RegExp(r'[|\[\]()<>“”"«»:：؛;!,،]'), ' ')
    .replaceAll(RegExp(r'[^\u0600-\u06FF0-9/ .\-]'), ' ')
    .replaceAll(RegExp(r'\s*\.+\s*$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _keepYa = {'موسي', 'عيسي', 'مصطفي', 'يحيي', 'ليلي', 'سلمي', 'هدي', 'مني', 'ندي', 'رضوي', 'حتي', 'سلوي', 'نجوي', 'دعاء'};

const _hamza = {
  'احمد': 'أحمد', 'ابراهيم': 'إبراهيم', 'اسماعيل': 'إسماعيل', 'اسامه': 'أسامة',
  'ايمن': 'أيمن', 'امير': 'أمير', 'اميره': 'أميرة', 'امينه': 'أمينة',
  'اميمه': 'أميمة', 'ايه': 'آية', 'ايات': 'آيات', 'اسراء': 'إسراء',
  'اسلام': 'إسلام', 'ايهاب': 'إيهاب', 'اشرف': 'أشرف', 'انس': 'أنس',
  'اسماء': 'أسماء', 'الاء': 'آلاء', 'ادم': 'آدم', 'اياد': 'إياد',
};

String _cleanName(String s) {
  var t = s
      .replaceAll(RegExp(r'[^\u0600-\u06FF ]'), ' ')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final words = t.split(' ').map((w) {
    final hz = _hamza[_norm(w)];
    if (hz != null) return hz;
    if (w.endsWith('ى') && !_keepYa.contains(_norm(w))) {
      return '${w.substring(0, w.length - 1)}ي';
    }
    return w;
  });
  return words.join(' ');
}

const _headerWords = [
  'بيانات', 'المولود', 'الاب', 'الام', 'صوره', 'قيد', 'الميلاد', 'جمهوري',
  'وزاره', 'الداخلي', 'مصر', 'الجنسي', 'الديان', 'محل', 'تاريخ', 'رقم',
  'القومي', 'سنه', 'عام', 'جهه',
];

bool _isNameLike(OcrSeg s) {
  final raw = s.text;
  if (_colon.hasMatch(raw)) return false;
  if (RegExp(r'\d').hasMatch(raw)) return false;
  final n = _arabicOnly(raw);
  if (n.length < 3) return false;
  if (s.conf < 40) return false;
  if (_classify(raw).kind.isNotEmpty) return false;
  final words = _norm(raw)
      .replaceAll(RegExp(r'[^\u0621-\u064A ]'), ' ')
      .split(' ')
      .where((w) => w.length > 1)
      .toList();
  if (words.isEmpty) return false;
  final first = words.first;
  if (first.startsWith('الدي') || RegExp(r'^ال[جح][نمسص]').hasMatch(first)) {
    return false;
  }
  for (final w in words) {
    for (final h in _headerWords) {
      if (w == h || (h.length >= 5 && _lev(w, h) <= 1)) return false;
    }
  }
  return true;
}

String? _religion(String v, {required bool female}) {
  final n = _arabicOnly(v);
  if (n.isEmpty) return null;
  const opts = ['مسلم', 'مسلمه', 'مسيحي', 'مسيحيه', 'يهودي', 'يهوديه'];
  String? best;
  var bd = 99;
  for (final o in opts) {
    final d = _lev(n, o);
    if (d < bd) {
      bd = d;
      best = o;
    }
  }
  if (best == null || bd > 2) return null;
  const out = {
    'مسلم': 'مسلم', 'مسلمه': 'مسلمة', 'مسيحي': 'مسيحي',
    'مسيحيه': 'مسيحية', 'يهودي': 'يهودي', 'يهوديه': 'يهودية',
  };
  var r = out[best]!;
  if (female && r == 'مسلم' && n.endsWith('ه')) r = 'مسلمة';
  return r;
}

String? _nationality(String v) {
  final n = _arabicOnly(v);
  if (n.isEmpty) return null;
  if (_lev(n, 'مصر') <= 1 || _lev(n, 'مصري') <= 1) return 'مصر';
  return _cleanValue(v).isEmpty ? null : _cleanValue(v);
}

const _governorates = [
  'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'البحيرة', 'الشرقية',
  'الغربية', 'المنوفية', 'القليوبية', 'كفر الشيخ', 'الفيوم', 'بني سويف',
  'المنيا', 'أسيوط', 'سوهاج', 'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر',
  'الوادي الجديد', 'مطروح', 'شمال سيناء', 'جنوب سيناء', 'بورسعيد',
  'الإسماعيلية', 'السويس', 'دمياط',
];

String _fixPlace(String v) {
  final t = _cleanValue(v);
  if (t.isEmpty) return t;
  final parts = t.split('/');
  final first = _arabicOnly(parts.first);
  for (final g in _governorates) {
    final gn = _arabicOnly(g);
    if (first.isNotEmpty && _lev(first, gn) <= (gn.length >= 6 ? 2 : 1)) {
      parts[0] = g;
      break;
    }
  }
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' / ');
}

String? _nidOf(OcrSeg s) {
  final d = s.text.replaceAll(RegExp(r'\D'), '');
  if (d.length == 14 && RegExp(r'^[23]').hasMatch(d)) return d;
  if (d.length == 15) {
    for (var i = 0; i + 14 <= d.length; i++) {
      final c = d.substring(i, i + 14);
      if (RegExp(r'^[23]').hasMatch(c)) return c;
    }
  }
  return null;
}

// ───────── main entry ─────────

/// Field values read from the layout. Only fields found with some confidence
/// are returned; the caller fills the rest from the plain-text parser.
Map<String, String> parseLayout(List<OcrSeg> segs) {
  final out = <String, String>{};
  if (segs.isEmpty) return out;
  final lbl = [for (final s in segs) _classify(s.text)];

  List<int> idx(String kind) =>
      [for (var i = 0; i < segs.length; i++) if (lbl[i].kind == kind) i];

  final nidIdx = [
    for (var i = 0; i < segs.length; i++)
      if (_nidOf(segs[i]) != null) i
  ];
  final relIdx = idx('religion');
  final natIdx = idx('nat');

  // Parent NIDs: the last two national IDs on the page (child's comes first).
  int? motherNid, fatherNid, childNid;
  if (nidIdx.length >= 3) {
    childNid = nidIdx[nidIdx.length - 3];
  }
  if (nidIdx.isNotEmpty) motherNid = nidIdx.last;
  if (nidIdx.length >= 2) fatherNid = nidIdx[nidIdx.length - 2];
  if (nidIdx.length == 1) {
    // Single ID: cannot tell whose it is from position alone; leave to the
    // plain-text parser.
    motherNid = null;
  }
  if (fatherNid != null) out['fatherNid'] = _nidOf(segs[fatherNid])!;
  if (motherNid != null) out['motherNid'] = _nidOf(segs[motherNid])!;
  if (childNid != null) out['nid'] = _nidOf(segs[childNid])!;

  // Religion / nationality labels per block.
  int? pickAbove(List<int> list, int? anchor, {int? above}) {
    // last label whose top is above the anchor (and below `above`)
    int? best;
    for (final i in list) {
      if (anchor != null && segs[i].top >= segs[anchor].top) continue;
      if (above != null && segs[i].top <= above) continue;
      best = i;
    }
    return best;
  }

  int? fRel, mRel, cRel, fNat, mNat, cNat;
  // Label of a block = the one just above its national ID: within a window
  // of about half the distance between the father's and mother's ID rows.
  final window = (fatherNid != null && motherNid != null)
      ? ((segs[motherNid].top - segs[fatherNid].top) * 0.62).round()
      : 0;
  int? nearAbove(List<int> list, int? nid) {
    if (nid == null || window <= 0) return null;
    int? best;
    for (final i in list) {
      final d = segs[nid].top - segs[i].top;
      if (d > 0 && d <= window) best = i;
    }
    return best;
  }

  if (relIdx.length == 3) {
    cRel = relIdx[0];
    fRel = relIdx[1];
    mRel = relIdx[2];
  } else {
    mRel = nearAbove(relIdx, motherNid);
    fRel = nearAbove(relIdx, fatherNid);
    for (final i in relIdx) {
      if (i != mRel && i != fRel && (fatherNid == null || segs[i].top < segs[fatherNid].top - window)) {
        cRel = i;
        break;
      }
    }
  }
  if (natIdx.length == 3) {
    cNat = natIdx[0];
    fNat = natIdx[1];
    mNat = natIdx[2];
  } else {
    mNat = nearAbove(natIdx, motherNid);
    fNat = nearAbove(natIdx, fatherNid);
    for (final i in natIdx) {
      if (i != mNat && i != fNat && (fatherNid == null || segs[i].top < segs[fatherNid].top - window)) {
        cNat = i;
        break;
      }
    }
  }

  String valueOf(int labelIdx) {
    final v = _cleanValue(lbl[labelIdx].value);
    if (v.isNotEmpty) return v;
    // value in another segment of the same row, to the left of the label
    final s = segs[labelIdx];
    final cand = [
      for (var i = 0; i < segs.length; i++)
        if (i != labelIdx &&
            segs[i].row == s.row &&
            segs[i].right <= s.left + 5 &&
            lbl[i].kind.isEmpty)
          i
    ]..sort((a, b) => segs[b].left.compareTo(segs[a].left));
    return cand.map((i) => _cleanValue(segs[i].text)).join(' ').trim();
  }

  void religion(String key, int? i, bool female) {
    if (i == null) return;
    final r = _religion(valueOf(i), female: female);
    if (r != null) out[key] = r;
  }

  void nat(String key, int? i) {
    if (i == null) return;
    final r = _nationality(valueOf(i));
    if (r != null) out[key] = r;
  }

  religion('childReligion', cRel, false);
  religion('fatherReligion', fRel, false);
  religion('motherReligion', mRel, true);
  nat('childNat', cNat);
  nat('fatherNat', fNat);
  nat('motherNat', mNat);

  // Names: the closest name-like segment above each block's religion label.
  final nameIdx = [
    for (var i = 0; i < segs.length; i++)
      if (_isNameLike(segs[i])) i
  ];
  int? nameAbove(int? rel, {int? lowerBound}) {
    if (rel == null) return null;
    int? best;
    for (final i in nameIdx) {
      if (segs[i].top >= segs[rel].top) continue;
      if (lowerBound != null && segs[i].top <= lowerBound) continue;
      best = i;
    }
    return best;
  }

  final mName = nameAbove(mRel ?? motherNid,
      lowerBound: fatherNid != null ? segs[fatherNid].top : null);
  final fName = nameAbove(fRel ?? fatherNid);
  if (fName != null) out['fatherName'] = _cleanName(segs[fName].text);
  if (mName != null) out['motherName'] = _cleanName(segs[mName].text);

  // Child name: same row as the child's religion/nationality label, otherwise
  // the closest name-like line just above/below inside the child block.
  final childLabelRows = {
    for (final i in [cRel, cNat])
      if (i != null) segs[i].row
  };
  final fatherTop = fName != null
      ? segs[fName].top
      : (fRel != null
          ? segs[fRel].top
          : (fatherNid != null ? segs[fatherNid].top : 1 << 30));
  int? cName;
  for (final i in nameIdx) {
    if (segs[i].top >= fatherTop) continue;
    if (childLabelRows.contains(segs[i].row)) {
      cName = i;
      break;
    }
  }
  if (cName != null) out['name'] = _cleanName(segs[cName].text);

  // Child fields: gender, place, date, all above the father block.
  for (var i = 0; i < segs.length; i++) {
    if (segs[i].top >= fatherTop) break;
    final k = lbl[i].kind;
    if (k == 'gender' && !out.containsKey('gender')) {
      final g = _gender(lbl[i].value + ' ' + valueOfRow(segs, lbl, i));
      if (g != null) out['gender'] = g;
    }
    if (k == 'place' && !out.containsKey('birthPlace')) {
      final p = _fixPlace(valueOf(i));
      if (p.isNotEmpty) out['birthPlace'] = p;
    }
  }
  if (!out.containsKey('gender')) {
    for (var i = 0; i < segs.length; i++) {
      if (segs[i].top >= fatherTop) break;
      final t = _arabicOnly(segs[i].text);
      if (t.length >= 4 && t.endsWith('كر') && t.length <= 8) {
        out['gender'] = 'ذكر';
        break;
      }
    }
  }
  return out;
}

String valueOfRow(List<OcrSeg> segs, List<_Lbl> lbl, int i) {
  final s = segs[i];
  return [
    for (var j = 0; j < segs.length; j++)
      if (j != i && segs[j].row == s.row && lbl[j].kind.isEmpty) segs[j].text
  ].join(' ');
}

String? _gender(String v) {
  final n = _arabicOnly(v);
  if (n.isEmpty) return null;
  if (n.contains('انث') || n.endsWith('ثي') || n.endsWith('ثه')) return 'أنثى';
  if (n.contains('ذكر') || n.endsWith('كر')) return 'ذكر';
  return null;
}
