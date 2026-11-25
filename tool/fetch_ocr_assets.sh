#!/bin/sh
# Downloads the OCR engine files and language models into web/ before the build.
# (tesseract.js core 4.0.3 matches worker 4.0.2; ara = tessdata_best.)
set -e
cd "$(dirname "$0")/../web"
mkdir -p lang
for f in tesseract-core.wasm.js tesseract-core-simd.wasm.js; do
  curl -fsSL -o "$f" "https://unpkg.com/tesseract.js-core@v4.0.3/$f"
done
curl -fsSL -o /tmp/ara.traineddata https://github.com/tesseract-ocr/tessdata_best/raw/main/ara.traineddata
curl -fsSL -o /tmp/eng.traineddata https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata
gzip -9 -c /tmp/ara.traineddata > lang/ara.traineddata.gz
gzip -9 -c /tmp/eng.traineddata > lang/eng.traineddata.gz
ls -l . lang
