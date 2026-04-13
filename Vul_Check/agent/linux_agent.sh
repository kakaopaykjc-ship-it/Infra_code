#!/bin/bash
# ============================================================
# Linux 취약점 점검 에이전트
# 역할: 점검 스크립트 실행 → 결과 파싱 → 관리 서버에 전송
# ============================================================

# ── 설정 (환경에 맞게 수정) ──────────────────────────────────
MGMT_URL="http://관리서버IP:5100/api/report"
API_KEY="change-me-api-key"
SCRIPT_PATH="$(cd "$(dirname "$0")/.." && pwd)/Linux_Vul_Check.sh"
# ────────────────────────────────────────────────────────────

set -e

echo "[*] 취약점 점검 시작: $(date)"

# 점검 스크립트 실행
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "[!] 점검 스크립트를 찾을 수 없습니다: $SCRIPT_PATH"
    exit 1
fi
bash "$SCRIPT_PATH"

# 결과 파일 확인
RESULT_FILE=$(ls -t vuln_check_result_*.txt 2>/dev/null | head -1)
if [ -z "$RESULT_FILE" ]; then
    echo "[!] 결과 파일을 찾을 수 없습니다."
    exit 1
fi
echo "[*] 결과 파일: $RESULT_FILE"

# 서버 정보 수집
HOSTNAME=$(hostname)
IP=$(hostname -I 2>/dev/null | awk '{print $1}')

# 결과 파싱 및 전송 (Python3 인라인)
python3 - "$RESULT_FILE" "$HOSTNAME" "$IP" "$MGMT_URL" "$API_KEY" <<'PYEOF'
import sys, re, json
from urllib.request import Request, urlopen
from urllib.error import URLError

result_file, hostname, ip, url, api_key = sys.argv[1:]

with open(result_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 블록 분리 (구분선 기준)
blocks = re.split(r'-{20,}', content)
results = []

for block in blocks:
    block = block.strip()
    if not block:
        continue

    code_m   = re.search(r'\[(U_\d+)\]\s*(.+)', block)
    result_m = re.search(r'결과\s*:\s*(\S+)', block)
    detail_m = re.search(r'상세내용:\s*(.+)', block, re.DOTALL)

    if code_m and result_m:
        results.append({
            "code":   code_m.group(1).strip(),
            "name":   code_m.group(2).strip(),
            "result": result_m.group(1).strip(),
            "detail": detail_m.group(1).strip().split('\n')[0] if detail_m else "",
        })

if not results:
    print("[!] 파싱된 결과가 없습니다. 결과 파일 형식을 확인하세요.")
    sys.exit(1)

payload = json.dumps({
    "hostname": hostname,
    "os":       "linux",
    "ip":       ip,
    "results":  results,
}, ensure_ascii=False).encode("utf-8")

req = Request(url, data=payload, headers={
    "Content-Type": "application/json",
    "X-API-Key":    api_key,
}, method="POST")

try:
    with urlopen(req, timeout=30) as res:
        body = res.read().decode()
        print(f"[*] 전송 완료 ({len(results)}개 항목): {body}")
except URLError as e:
    print(f"[!] 전송 실패: {e}")
    sys.exit(1)
PYEOF

echo "[*] 완료: $(date)"
