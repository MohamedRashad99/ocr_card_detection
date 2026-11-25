// Layout-aware OCR for Egyptian birth certificates (runs fully in the browser).
// 1) Remove the guilloche background (local-contrast dark-ink mask).
// 2) Split the page into text lines (row projection) and then into segments
//    (column gaps), so each label/value/name/number is its own small image.
// 3) OCR every segment alone (tesseract.js, single-line mode). Segments with
//    no Arabic letters are re-read with the English digits model (national IDs).
// 4) Return the segments in reading order (top to bottom, right to left), one
//    per line, for the Dart parser.
(function () {
  var base = document.baseURI;
  var SIMD_TEST = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11]);
  function hasSimd() {
    try { return WebAssembly.validate(SIMD_TEST); } catch (e) { return false; }
  }
  var LOCAL = {
    workerPath: new URL('worker.min.js', base).href,
    corePath: new URL(hasSimd() ? 'tesseract-core-simd.wasm.js' : 'tesseract-core.wasm.js', base).href,
    langPath: new URL('lang', base).href,
    gzip: true,
  };
  var REMOTE = {
    workerPath: 'https://unpkg.com/tesseract.js@v4.0.2/dist/worker.min.js',
    corePath: 'https://unpkg.com/tesseract.js-core@v4.0.3/tesseract-core.wasm.js',
    langPath: 'https://tessdata.projectnaptha.com/4.0.0_best',
    gzip: true,
  };

  window.__tessReady = new Promise(function (resolve, reject) {
    var s = document.createElement('script');
    s.src = new URL('tesseract.min.js', base).href;
    s.onload = function () { resolve(); };
    s.onerror = function () { reject(new Error('tesseract.js failed to load')); };
    document.head.appendChild(s);
  });

  async function loadImage(url) {
    var img = new Image();
    img.src = url;
    await img.decode();
    return img;
  }

  // Draw the photo at a normalized size (long side 1400 px) so every
  // threshold below is resolution independent.
  function toCanvas(img) {
    var ow = img.naturalWidth, oh = img.naturalHeight;
    var scale = 1400 / Math.max(ow, oh);
    var w = Math.max(1, Math.round(ow * scale)), h = Math.max(1, Math.round(oh * scale));
    var c = document.createElement('canvas');
    c.width = w; c.height = h;
    var ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(img, 0, 0, w, h);
    return c;
  }

  // Dark ink = clearly darker than its own neighbourhood and dark overall.
  function inkMask(canvas) {
    var w = canvas.width, h = canvas.height;
    var px = canvas.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, w, h).data;
    var g = new Float32Array(w * h);
    for (var i = 0, j = 0; i < px.length; i += 4, j++) {
      g[j] = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
    }
    // integral image for a box blur
    var W1 = w + 1;
    var integ = new Float64Array(W1 * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        rowSum += g[y * w + x];
        integ[(y + 1) * W1 + x + 1] = integ[y * W1 + x + 1] + rowSum;
      }
    }
    var r = Math.max(8, Math.round(Math.max(w, h) * 0.0165));
    var mask = new Uint8Array(w * h);
    for (var y2 = 0; y2 < h; y2++) {
      var y0 = Math.max(0, y2 - r), y1 = Math.min(h, y2 + r + 1);
      for (var x2 = 0; x2 < w; x2++) {
        var x0 = Math.max(0, x2 - r), x1 = Math.min(w, x2 + r + 1);
        var area = (y1 - y0) * (x1 - x0);
        var sum = integ[y1 * W1 + x1] - integ[y0 * W1 + x1] - integ[y1 * W1 + x0] + integ[y0 * W1 + x0];
        var bg = sum / area;
        var v = g[y2 * w + x2];
        if (bg - v > 35 && v < 135) mask[y2 * w + x2] = 1;
      }
    }
    removeLines(mask, w, h);
    return { mask: mask, w: w, h: h };
  }

  // Thin straight rules (section borders, the frame around the registry
  // box) are not text: erase long, thin runs so they do not form fake lines.
  function removeLines(mask, w, h) {
    var minH = Math.round(w * 0.28), minV = Math.round(h * 0.09), d = 4;
    function density(x0, x1, y) {
      if (y < 0 || y >= h) return 0;
      var c = 0;
      for (var x = x0; x < x1; x++) c += mask[y * w + x];
      return c / Math.max(1, x1 - x0);
    }
    for (var y = 0; y < h; y++) {
      var st = -1;
      for (var x = 0; x <= w; x++) {
        var on = x < w && mask[y * w + x];
        if (on && st < 0) st = x;
        if (!on && st >= 0) {
          if (x - st >= minH && density(st, x, y - d) < 0.2 && density(st, x, y + d) < 0.2) {
            for (var xx = st; xx < x; xx++) {
              for (var dy = -1; dy <= 1; dy++) if (y + dy >= 0 && y + dy < h) mask[(y + dy) * w + xx] = 0;
            }
          }
          st = -1;
        }
      }
    }
    for (var x2 = 0; x2 < w; x2++) {
      var sy = -1;
      for (var y2 = 0; y2 <= h; y2++) {
        var on2 = y2 < h && mask[y2 * w + x2];
        if (on2 && sy < 0) sy = y2;
        if (!on2 && sy >= 0) {
          if (y2 - sy >= minV) {
            var sideL = 0, sideR = 0;
            for (var yy = sy; yy < y2; yy++) {
              if (x2 - d >= 0) sideL += mask[yy * w + x2 - d];
              if (x2 + d < w) sideR += mask[yy * w + x2 + d];
            }
            var len = y2 - sy;
            if (sideL / len < 0.2 && sideR / len < 0.2) {
              for (var yc = sy; yc < y2; yc++) {
                for (var dx = -1; dx <= 1; dx++) if (x2 + dx >= 0 && x2 + dx < w) mask[yc * w + x2 + dx] = 0;
              }
            }
          }
          sy = -1;
        }
      }
    }
  }

  function smooth(arr, k) {
    var out = new Float32Array(arr.length), half = k >> 1;
    var acc = 0, n = arr.length;
    for (var i = -half; i < n + half; i++) {
      if (i + half < n) acc += arr[i + half];
      if (i - half - 1 >= 0) acc -= arr[i - half - 1];
      if (i >= 0 && i < n) out[i] = acc / k;
    }
    return out;
  }

  // Segment into [top, bottom, left, right] boxes in reading order.
  function segment(m) {
    var w = m.w, h = m.h, mask = m.mask;
    var rows = new Float32Array(h);
    for (var y = 0; y < h; y++) {
      var s = 0, o = y * w;
      for (var x = 0; x < w; x++) s += mask[o + x];
      rows[y] = s;
    }
    var sm = smooth(rows, 5);
    var mx = 0;
    for (var i = 0; i < h; i++) if (sm[i] > mx) mx = sm[i];
    var thr = Math.max(3, mx * 0.06);
    var minLineH = Math.max(10, Math.round(h * 0.0095));
    var lines = [], start = -1;
    for (var yy = 0; yy <= h; yy++) {
      var on = yy < h && sm[yy] > thr;
      if (on && start < 0) start = yy;
      if (!on && start >= 0) {
        if (yy - start >= minLineH) lines.push([start, yy]);
        start = -1;
      }
    }
    // Split tall blocks (e.g. the registry box, lines packed together) at
    // their row-sum valleys.
    var hs = lines.map(function (l) { return l[1] - l[0]; }).sort(function (p, q) { return p - q; });
    var med = hs.length ? hs[Math.floor(hs.length / 2)] : 30;
    var split = [];
    for (var bi = 0; bi < lines.length; bi++) {
      var la = lines[bi][0], lb = lines[bi][1];
      if (lb - la < med * 2.3) { split.push(lines[bi]); continue; }
      var sm2 = smooth(rows, 3), bmax = 0;
      for (var t1 = la; t1 < lb; t1++) if (sm2[t1] > bmax) bmax = sm2[t1];
      var cut = la, y4 = la + Math.round(med * 0.6);
      while (y4 < lb - Math.round(med * 0.6)) {
        if (sm2[y4] < bmax * 0.3 && y4 - cut >= med * 0.7) {
          var ve = y4;
          while (ve < lb && sm2[ve] < bmax * 0.3) ve++;
          split.push([cut, y4]);
          cut = ve; y4 = ve + Math.round(med * 0.6);
        } else y4++;
      }
      split.push([cut, lb]);
    }
    lines = split;
    var gap = Math.round(w * 0.035);
    var minW = Math.max(12, Math.round(w * 0.016));
    var segs = [];
    for (var li = 0; li < lines.length; li++) {
      var a = lines[li][0], b = lines[li][1];
      var cols = new Uint8Array(w);
      for (var y3 = a; y3 < b; y3++) {
        var o2 = y3 * w;
        for (var x3 = 0; x3 < w; x3++) if (mask[o2 + x3]) cols[x3] = 1;
      }
      var runs = [], rs = -1;
      for (var xx = 0; xx <= w; xx++) {
        var c = xx < w && cols[xx];
        if (c && rs < 0) rs = xx;
        if (!c && rs >= 0) { runs.push([rs, xx]); rs = -1; }
      }
      var merged = [];
      for (var k = 0; k < runs.length; k++) {
        var last = merged[merged.length - 1];
        if (last && runs[k][0] - last[1] < gap) last[1] = runs[k][1];
        else merged.push([runs[k][0], runs[k][1]]);
      }
      var lineSegs = [];
      for (var q = 0; q < merged.length; q++) {
        if (merged[q][1] - merged[q][0] >= minW) lineSegs.push([a, b, merged[q][0], merged[q][1]]);
      }
      lineSegs.sort(function (p, q2) { return q2[2] - p[2]; }); // right to left
      for (var z = 0; z < lineSegs.length; z++) segs.push(lineSegs[z]);
    }
    return segs;
  }

  // Render one segment as black text on white at a fixed text height. Word
  // gaps are widened to a clear space so the OCR does not glue words together.
  function segmentImage(m, seg, words, targetH) {
    var padY = 6, padX = 8;
    var y0 = Math.max(0, seg[0] - padY), y1 = Math.min(m.h, seg[1] + padY);
    var sh = y1 - y0;
    var ranges;
    if (words && words.length > 1) {
      ranges = words.slice().sort(function (p, q) { return p[2] - q[2]; })
        .map(function (w) { return [w[2], w[3]]; });
    } else {
      ranges = [[Math.max(0, seg[2] - padX), Math.min(m.w, seg[3] + padX)]];
    }
    var spacing = Math.round(sh * 0.7);
    var sw = padX * 2;
    for (var r = 0; r < ranges.length; r++) sw += ranges[r][1] - ranges[r][0] + (r ? spacing : 0);
    var small = document.createElement('canvas');
    small.width = sw; small.height = sh;
    var sctx = small.getContext('2d');
    var id = sctx.createImageData(sw, sh);
    for (var i = 0; i < id.data.length; i++) id.data[i] = 255;
    var ox = padX;
    for (var q = 0; q < ranges.length; q++) {
      for (var x = ranges[q][0]; x < ranges[q][1]; x++, ox++) {
        for (var y = 0; y < sh; y++) {
          if (m.mask[(y0 + y) * m.w + x]) {
            var p = (y * sw + ox) * 4;
            id.data[p] = id.data[p + 1] = id.data[p + 2] = 0;
          }
        }
      }
      ox += spacing;
    }
    sctx.putImageData(id, 0, 0);
    var sc = (targetH || 64) / sh;
    var margin = 20;
    var big = document.createElement('canvas');
    big.width = Math.round(sw * sc) + margin * 2;
    big.height = Math.round(sh * sc) + margin * 2;
    var bctx = big.getContext('2d');
    bctx.fillStyle = '#fff';
    bctx.fillRect(0, 0, big.width, big.height);
    bctx.imageSmoothingEnabled = true;
    bctx.imageSmoothingQuality = 'high';
    bctx.drawImage(small, margin, margin, Math.round(sw * sc), Math.round(sh * sc));
    return big;
  }

  function arabicCount(t) { return (t.match(/[\u0600-\u06FF]/g) || []).length; }

  function lev(a, b) {
    var prev = [], i, j;
    for (j = 0; j <= b.length; j++) prev.push(j);
    for (i = 1; i <= a.length; i++) {
      var cur = [i];
      for (j = 1; j <= b.length; j++) {
        cur.push(Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  function letters(t) { return t.replace(/[^\u0621-\u064A]/g, ''); }

  function wordCount(t) { return t.split(/\s+/).filter(function (w) { return /[\u0600-\u06FF]/.test(w); }).length; }

  // National IDs are exactly 14 digits; the OCR sometimes adds a stray digit.
  function cleanNid(d) {
    d = d.replace(/\D/g, '');
    if (d.length <= 14) return d;
    for (var i = 0; i + 14 <= d.length; i++) {
      var c = d.substr(i, 14);
      var mm = parseInt(c.substr(3, 2), 10), dd = parseInt(c.substr(5, 2), 10);
      if (/^[23]/.test(c) && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) return c;
    }
    for (var j = 0; j + 14 <= d.length; j++) if (/^[23]/.test(d.substr(j, 14))) return d.substr(j, 14);
    return d.substr(0, 14);
  }

  async function recText(worker, canvas, psm) {
    await worker.setParameters({ tessedit_pageseg_mode: psm, preserve_interword_spaces: '1', user_defined_dpi: '300' });
    var r = await worker.recognize(canvas);
    return {
      text: ((r.data && r.data.text) || '').replace(/\s+/g, ' ').trim(),
      conf: (r.data && r.data.confidence) || 0,
    };
  }

  // Word boundaries inside a segment: column gaps wider than 0.36 x line height.
  function wordBoxes(m, seg) {
    var a = seg[0], b = seg[1], th = b - a;
    var cols = [];
    for (var x = seg[2]; x < seg[3]; x++) {
      var on = 0;
      for (var y = a; y < b; y++) if (m.mask[y * m.w + x]) { on = 1; break; }
      cols.push(on);
    }
    var runs = [], st = -1;
    for (var i = 0; i <= cols.length; i++) {
      var c = i < cols.length && cols[i];
      if (c && st < 0) st = i;
      if (!c && st >= 0) { runs.push([st, i]); st = -1; }
    }
    var words = [];
    for (var k = 0; k < runs.length; k++) {
      var last = words[words.length - 1];
      if (last && runs[k][0] - last[1] < th * 0.36) last[1] = runs[k][1];
      else words.push([runs[k][0], runs[k][1]]);
    }
    return words.map(function (w) { return [a, b, seg[2] + w[0], seg[2] + w[1]]; })
      .sort(function (p, q) { return q[2] - p[2]; });
  }

  async function readSegment(ara, eng, m, seg) {
    var wb = wordBoxes(m, seg);
    var plainCanvas = segmentImage(m, seg, null);
    var canvas = plainCanvas;
    var spaced = null;
    var r = await recText(ara, canvas, '7');
    if (!r.text && wb.length <= 6) r = await recText(ara, canvas, '13');
    if (arabicCount(r.text) < 4) {
      await eng.setParameters({ tessedit_pageseg_mode: '7', tessedit_char_whitelist: '0123456789', user_defined_dpi: '300' });
      var d = await eng.recognize(plainCanvas);
      var digits = ((d.data && d.data.text) || '').replace(/\s+/g, '');
      if ((digits.match(/\d/g) || []).length >= 8) {
        return { t: digits.length > 14 ? cleanNid(digits) : digits, conf: (d.data && d.data.confidence) || 0, digits: true };
      }
    }
    // Words glued together: retry with widened gaps, keep it only if it adds
    // spaces without lowering confidence much.
    if (arabicCount(r.text) >= 5 && r.conf >= 45 && wb.length > 1 && wb.length <= 6 && wordCount(r.text) < wb.length) {
      var tries = [64, 90, 76, 100];
      for (var ti = 0; ti < tries.length && wordCount(r.text) < wb.length; ti++) {
        var r3 = await recText(ara, segmentImage(m, seg, null, tries[ti]), '13');
        var sameLetters = lev(letters(r3.text), letters(r.text)) <= 1;
        if (wordCount(r3.text) > wordCount(r.text) && wordCount(r3.text) <= wb.length && (sameLetters || r3.conf >= r.conf - 15)) r = r3;
      }
    }
    return { t: r.text, conf: r.conf };
  }

  async function runWith(src, imageUrl, mapData) {
    var araWorker, engWorker;
    try {
      araWorker = await Tesseract.createWorker(src);
      await araWorker.loadLanguage('ara');
      await araWorker.initialize('ara');
      engWorker = await Tesseract.createWorker(src);
      await engWorker.loadLanguage('eng');
      await engWorker.initialize('eng');
      var img = await loadImage(imageUrl);
      var canvas = toCanvas(img);
      var m = inkMask(canvas);
      var segs = segment(m);
      var out = [], row = -1, lastTop = -1;
      for (var i = 0; i < segs.length; i++) {
        var rd = await readSegment(araWorker, engWorker, m, segs[i]);
        if (!rd.t) continue;
        if (segs[i][0] !== lastTop) { row++; lastTop = segs[i][0]; }
        out.push({ t: rd.t, conf: Math.round(rd.conf), digits: !!rd.digits, row: row,
          top: segs[i][0], bottom: segs[i][1], left: segs[i][2], right: segs[i][3] });
      }
      if (!out.length) return '';
      return JSON.stringify({ v: 2, w: m.w, h: m.h, segs: out });
    } finally {
      try { if (araWorker) await araWorker.terminate(); } catch (_) {}
      try { if (engWorker) await engWorker.terminate(); } catch (_) {}
    }
  }

  async function _extractText(imageUrl, mapData) {
    try {
      await window.__tessReady;
    } catch (e) {
      return '__OCR_ERROR__: ' + (e && e.message ? e.message : String(e));
    }
    var lastError = 'unknown error';
    var sources = [LOCAL, REMOTE];
    for (var s = 0; s < sources.length; s++) {
      try {
        var text = await runWith(sources[s], imageUrl, mapData);
        if (text) return text;
        lastError = 'no text found';
      } catch (e) {
        lastError = e && e.message ? e.message : String(e);
        console.warn('OCR failed with', sources[s].langPath, e);
      }
    }
    return '__OCR_ERROR__: ' + lastError;
  }

  window._extractText = _extractText;
})();
