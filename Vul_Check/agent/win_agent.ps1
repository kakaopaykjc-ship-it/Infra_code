# ============================================================
# Windows 취약점 점검 에이전트
# 역할: 점검 스크립트 실행 → 결과 파싱 → 관리 서버에 전송
# 실행: PowerShell -ExecutionPolicy Bypass -File win_agent.ps1
# ============================================================

# ── 설정 (환경에 맞게 수정) ──────────────────────────────────
$MgmtUrl = "http://관리서버IP:5100/api/report"
$ApiKey  = "change-me-api-key"
$ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Win_Vul_Check.ps1"
# ────────────────────────────────────────────────────────────

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "[*] 취약점 점검 시작: $(Get-Date)"

# 점검 스크립트 실행
if (-not (Test-Path $ScriptPath)) {
    Write-Error "[!] 점검 스크립트를 찾을 수 없습니다: $ScriptPath"
    exit 1
}
& PowerShell -ExecutionPolicy Bypass -File $ScriptPath

# 결과 파일 확인
$ResultFile = Get-ChildItem "Win_Vul_Check_Result_*.txt" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $ResultFile) {
    Write-Error "[!] 결과 파일을 찾을 수 없습니다."
    exit 1
}
Write-Host "[*] 결과 파일: $($ResultFile.Name)"

# 서버 정보 수집
$Hostname = $env:COMPUTERNAME
$IP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.IPAddress -ne "127.0.0.1" } |
       Select-Object -First 1).IPAddress

# 결과 파싱
$Content = Get-Content $ResultFile.FullName -Encoding UTF8 -Raw
$Blocks  = $Content -split '-{20,}'
$Results = [System.Collections.Generic.List[hashtable]]::new()

foreach ($Block in $Blocks) {
    $Block = $Block.Trim()
    if (-not $Block) { continue }

    $CodeMatch   = [regex]::Match($Block, '\[(W-\d+)\]\s*(.+)')
    $ResultMatch = [regex]::Match($Block, '결과\s*:\s*(\S+)')
    $DetailMatch = [regex]::Match($Block, '상세\s*:\s*(.+)', 'Singleline')

    if ($CodeMatch.Success -and $ResultMatch.Success) {
        $Results.Add(@{
            code   = $CodeMatch.Groups[1].Value.Trim()
            name   = $CodeMatch.Groups[2].Value.Trim()
            result = $ResultMatch.Groups[1].Value.Trim()
            detail = if ($DetailMatch.Success) { ($DetailMatch.Groups[1].Value -split "`n")[0].Trim() } else { "" }
        })
    }
}

if ($Results.Count -eq 0) {
    Write-Error "[!] 파싱된 결과가 없습니다. 결과 파일 형식을 확인하세요."
    exit 1
}

# JSON 직렬화
$Payload = @{
    hostname = $Hostname
    os       = "windows"
    ip       = $IP
    results  = $Results.ToArray()
} | ConvertTo-Json -Depth 4

# 관리 서버 전송
$Headers = @{
    "Content-Type" = "application/json"
    "X-API-Key"    = $ApiKey
}

try {
    $Body     = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $Response = Invoke-RestMethod -Uri $MgmtUrl -Method Post -Body $Body -Headers $Headers -TimeoutSec 30
    Write-Host "[*] 전송 완료 ($($Results.Count)개 항목): $($Response | ConvertTo-Json -Compress)"
} catch {
    Write-Error "[!] 전송 실패: $_"
    exit 1
}

Write-Host "[*] 완료: $(Get-Date)"
