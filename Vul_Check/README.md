# Vul_Check — 주요정보통신기반시설 취약점 점검 스크립트

KISA 주요정보통신기반시설 기술적 취약점 분석·평가 기준에 따라 Linux/Windows 서버를 자동 점검하는 스크립트.

---

## 파일 구조

```
Vul_Check/
├── Linux_Vul_Check.sh    # Linux/Unix 취약점 점검 스크립트 (U_01 ~ U_67)
├── Win_Vul_Check.txt     # Windows 취약점 점검 스크립트 (W-01 ~ W-64) — .ps1로 변경 후 사용
└── 사용 전 입력.txt       # 간단 사용 안내
```

---

## Linux 점검 스크립트 (`Linux_Vul_Check.sh`)

### 점검 항목
U_01 ~ U_67 (67개 항목) — KISA Unix/Linux 서버 취약점 점검 기준

### 결과 분류
| 결과 | 의미 |
|------|------|
| 양호 | 취약점 없음 |
| 취약 | 조치 필요 |
| 체크필요 | 수동 확인 필요 |

### 실행 방법

```bash
# 1. 실행 권한 부여
chmod +x Linux_Vul_Check.sh

# 2. root 권한으로 실행
sudo bash Linux_Vul_Check.sh
```

### 결과 파일
- 실행 디렉터리에 `vuln_check_result_YYYYMMDD.txt` 생성
- 항목별 결과(양호/취약/체크필요)와 상세 내용 기록
- 마지막 줄에 전체 통계 요약 출력

```
[U_01] root 계정 원격 접속 제한
결과 : 양호
상세내용: 루트 로그인제한 확인
---------------------------------------------------------
...
[점검 완료] 총 67건 | 양호: 50 | 취약: 10 | 체크필요: 7
```

---

## Windows 점검 스크립트 (`Win_Vul_Check.txt`)

### 사전 준비
파일 확장자를 `.ps1`로 변경 후 사용.

```powershell
# 파일 복사 또는 이름 변경
Copy-Item Win_Vul_Check.txt Win_Vul_Check.ps1
```

### 점검 항목
W-01 ~ W-64 (64개 항목) — KISA Windows 서버 취약점 점검 기준

### 실행 방법

> **관리자 권한 필수** — `secedit` 명령어 실행에 필요

```powershell
# PowerShell을 관리자 권한으로 열고 실행
PowerShell -ExecutionPolicy Bypass -File .\Win_Vul_Check.ps1
```

### 결과 파일
실행 디렉터리에 두 가지 파일 생성:

| 파일 | 내용 |
|------|------|
| `Win_Vul_Check_Result_YYYYMMDD.txt` | 항목별 상세 결과 텍스트 |
| `Win_Vul_Check_Result_YYYYMMDD.csv` | 스프레드시트용 CSV |

```
[W-01] Administrator 계정 이름 변경
결과 : 양호
상세 : 관리자 계정명이 변경되었습니다 (Admin_SMT).
----------------------------------------------
...
[점검 완료] 총 64건 | 양호: 48 | 취약: 12 | 체크필요: 4
```

---

## 주의사항

- **반드시 점검 대상 서버에서 직접 실행** (원격 점검 불가)
- Linux 스크립트는 `root` 또는 `sudo` 권한 필요
- Windows 스크립트는 PowerShell **관리자 권한** 필요
- 점검 결과 파일에 민감한 시스템 정보가 포함될 수 있으므로 외부 유출 주의
