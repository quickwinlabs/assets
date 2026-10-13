#!/bin/bash
# 临时:在 runner 上探测 tiny11 镜像源可达性(数据机 IP)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

echo "== archive.org metadata: tiny11_25H2 =="
curl -s --max-time 30 "https://archive.org/metadata/tiny11_25H2" > /tmp/meta.json || true
python3 - <<'EOF' || true
import json
try:
    d = json.load(open('/tmp/meta.json'))
    for f in d.get('files', []):
        print(f.get('name'), f.get('size'))
except Exception as e:
    print('parse fail:', e)
EOF

for q in "Tiny11Core+25H2" "tiny11+25h2+core"; do
  echo "== archive.org search: $q =="
  curl -s --max-time 30 "https://archive.org/advancedsearch.php?q=$q&fl%5B%5D=identifier&fl%5B%5D=title&rows=15&output=json" > /tmp/search.json || true
  python3 - <<'EOF' || true
import json
try:
    d = json.load(open('/tmp/search.json'))
    for doc in d['response']['docs']:
        print(doc.get('identifier'), '|', str(doc.get('title'))[:70])
except Exception as e:
    print('parse fail:', e)
EOF
done

echo "== sourceforge direct mirror hosts =="
F="project/tiny-11-releases/Tiny11Core-Pro-25H2/Tiny11Core-25H2-26200.8037-English-Pro-2026-08-23.iso"
for h in cfhcable versaweb netix pilotfiber phoenixnap cytranet freefr ixpeering; do
  code=$(curl -sI -A "$UA" -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 "https://$h.dl.sourceforge.net/$F" 2>/dev/null || echo ERR)
  echo "$h.dl.sourceforge.net → $code"
done

echo "== sf interstitial =="
curl -sIL -A "$UA" -o /dev/null -w '%{http_code} %{url_effective}\n' --connect-timeout 10 --max-time 30 "https://downloads.sourceforge.net/$F" || true
