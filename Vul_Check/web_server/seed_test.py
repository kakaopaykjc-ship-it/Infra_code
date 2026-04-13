"""테스트 데이터 삽입 스크립트 - 실제 서버 연동 전 UI 확인용"""
from app import app
from models import db, Server, CheckRun, CheckItem
from datetime import datetime

LINUX_ITEMS = [
    ("U_01", "root 계정 원격 접속 제한",        "양호",    "루트 로그인 제한 확인"),
    ("U_02", "패스워드 복잡성 설정",             "취약",    "패스워드 최소 길이 미설정"),
    ("U_03", "계정 잠금 임계값 설정",            "취약",    "로그인 실패 횟수 제한 없음"),
    ("U_04", "패스워드 파일 보호",               "양호",    "/etc/shadow 권한 정상"),
    ("U_05", "root 이외의 UID 0 계정 제거",      "양호",    "UID 0 계정 root만 존재"),
    ("U_06", "root 계정 Path 설정",              "체크필요", "PATH에 현재 디렉토리(.) 포함 여부 확인 필요"),
    ("U_07", "파일 및 디렉토리 소유자 설정",     "양호",    "소유자 없는 파일 없음"),
    ("U_08", "world writable 파일 점검",         "취약",    "world writable 파일 3개 발견"),
    ("U_09", "/dev에 불필요한 파일 존재 여부",   "양호",    "불필요한 파일 없음"),
    ("U_10", "$HOME/.rhosts 파일 제거",          "양호",    ".rhosts 파일 없음"),
    ("U_11", "hosts.equiv 파일 제거",            "양호",    "hosts.equiv 파일 없음"),
    ("U_12", "SUID / SGID 설정 파일 점검",       "체크필요", "SUID 설정 파일 12개 - 검토 필요"),
    ("U_13", "사용자 홈 디렉토리 권한 설정",     "취약",    "일부 홈 디렉토리 other 쓰기 허용"),
    ("U_14", "사용자 파일 생성 umask 설정",      "양호",    "umask 022 설정 확인"),
    ("U_15", "홈 디렉토리로 지정된 디렉토리 존재여부", "양호", "모든 홈 디렉토리 존재 확인"),
]

WIN_ITEMS = [
    ("W-01", "Administrator 계정 이름 변경",     "취약",    "관리자 계정명이 기본값(Administrator)"),
    ("W-02", "Guest 계정 비활성화",              "양호",    "Guest 계정 비활성화 확인"),
    ("W-03", "불필요한 계정 제거",               "체크필요", "비활성 계정 2개 확인 필요"),
    ("W-04", "계정 잠금 임계값 설정",            "취약",    "계정 잠금 정책 미설정"),
    ("W-05", "패스워드 복잡성 설정",             "양호",    "복잡성 요구사항 활성화 확인"),
    ("W-06", "패스워드 최대 사용 기간",          "취약",    "최대 사용 기간 무제한으로 설정됨"),
    ("W-07", "패스워드 최소 길이 설정",          "양호",    "최소 8자 설정 확인"),
    ("W-08", "로컬 로그인 허용 사용자 제한",     "체크필요", "로컬 로그인 허용 계정 확인 필요"),
    ("W-09", "원격 로그인 허용 사용자 제한",     "양호",    "원격 접속 권한 제한 확인"),
    ("W-10", "최근 로그인 사용자 표시 안함",     "취약",    "마지막 로그인 사용자 표시 활성화"),
]

with app.app_context():
    db.drop_all()
    db.create_all()

    # 서버 1: Linux
    s1 = Server(hostname="web-server-01", os_type="linux", ip="192.168.1.10",
                last_check_at=datetime.now())
    db.session.add(s1)
    db.session.flush()

    r1 = CheckRun(
        server_id=s1.id, check_time=datetime.now(),
        good_cnt=sum(1 for i in LINUX_ITEMS if i[2]=="양호"),
        vuln_cnt=sum(1 for i in LINUX_ITEMS if i[2]=="취약"),
        check_cnt=sum(1 for i in LINUX_ITEMS if i[2]=="체크필요"),
        total_cnt=len(LINUX_ITEMS),
    )
    db.session.add(r1)
    db.session.flush()
    for code, name, result, detail in LINUX_ITEMS:
        db.session.add(CheckItem(run_id=r1.id, code=code, name=name, result=result, detail=detail))

    # 서버 2: Linux (양호 비율 높음)
    s2 = Server(hostname="db-server-01", os_type="linux", ip="192.168.1.20",
                last_check_at=datetime.now())
    db.session.add(s2)
    db.session.flush()

    items2 = [(c, n, "양호", d) if r != "취약" else (c, n, r, d) for c, n, r, d in LINUX_ITEMS]
    r2 = CheckRun(
        server_id=s2.id, check_time=datetime.now(),
        good_cnt=sum(1 for i in items2 if i[2]=="양호"),
        vuln_cnt=sum(1 for i in items2 if i[2]=="취약"),
        check_cnt=sum(1 for i in items2 if i[2]=="체크필요"),
        total_cnt=len(items2),
    )
    db.session.add(r2)
    db.session.flush()
    for code, name, result, detail in items2:
        db.session.add(CheckItem(run_id=r2.id, code=code, name=name, result=result, detail=detail))

    # 서버 3: Windows
    s3 = Server(hostname="win-server-01", os_type="windows", ip="192.168.1.30",
                last_check_at=datetime.now())
    db.session.add(s3)
    db.session.flush()

    r3 = CheckRun(
        server_id=s3.id, check_time=datetime.now(),
        good_cnt=sum(1 for i in WIN_ITEMS if i[2]=="양호"),
        vuln_cnt=sum(1 for i in WIN_ITEMS if i[2]=="취약"),
        check_cnt=sum(1 for i in WIN_ITEMS if i[2]=="체크필요"),
        total_cnt=len(WIN_ITEMS),
    )
    db.session.add(r3)
    db.session.flush()
    for code, name, result, detail in WIN_ITEMS:
        db.session.add(CheckItem(run_id=r3.id, code=code, name=name, result=result, detail=detail))

    db.session.commit()
    print("✅ 테스트 데이터 삽입 완료!")
    print(f"   - {s1.hostname} (Linux): 취약 {r1.vuln_cnt} / 체크필요 {r1.check_cnt} / 양호 {r1.good_cnt}")
    print(f"   - {s2.hostname} (Linux): 취약 {r2.vuln_cnt} / 체크필요 {r2.check_cnt} / 양호 {r2.good_cnt}")
    print(f"   - {s3.hostname} (Windows): 취약 {r3.vuln_cnt} / 체크필요 {r3.check_cnt} / 양호 {r3.good_cnt}")
