# mapo_daily_check.sh 사용법

마포구청 LMS(MariaDB/Tomcat) 및 NetBox(Docker/PostgreSQL) 일일 점검 + 백업 스크립트.

## 주요 개선 사항 (기존 대비)

- **비밀번호 하드코딩 제거**: `mysqldump -proot` 대신 `~/.my.cnf` 또는 환경변수 사용
- **컨테이너명 하드코딩 제거**: `netbox-docker-postgres-1`을 고정하지 않고 실행 중인 컨테이너에서 자동 탐색
- **중복 실행 방지**: `flock` 기반 락 파일로 동시 실행 차단
- **종료코드 지원**: 점검 중 하나라도 FAIL이면 `exit 1` → cron/모니터링에서 실패 감지 가능
- **에러 로그 분리**: mysqldump/pg_dumpall/tar 에러를 `/tmp/daily_check/*.err`에 별도 기록
- **변수 인용/안전성**: `set -uo pipefail` 및 변수 quoting 적용
- **로그 자동 정리**: 백업파일과 동일하게 7일 지난 로그도 자동 삭제

## 사전 준비

### 1) MySQL 인증 설정 (택1)

**권장: `~/.my.cnf` 파일 사용** (점검 스크립트를 실행하는 사용자 홈 디렉터리)

```ini
[client]
user=root
password=실제비밀번호
```

```bash
chmod 600 ~/.my.cnf
```

**대안: 환경변수로 주입**

```bash
export MYSQL_USER=root
export MYSQL_DEFAULTS_FILE=/path/to/custom.my.cnf   # ~/.my.cnf가 아닌 다른 경로를 쓸 경우
```

`~/.my.cnf`가 없으면 비밀번호 없이 `-u $MYSQL_USER`로만 접속을 시도하므로, root 비밀번호가 설정된 환경에서는 반드시 `.my.cnf`를 만들어야 한다.

### 2) 실행 권한 부여

```bash
chmod +x mapo_daily_check.sh
```

## 실행 방법

```bash
./mapo_daily_check.sh
```

- 점검 진행 중 화면에 진행률(%)이 표시된다.
- 완료 후 LMS/NetBox 점검 결과와 백업파일 크기가 출력된다.
- 결과는 `/tmp/daily_check/mapo_daily_check_YYYYMMDD.log`에 누적 기록된다.
- 점검 항목 중 하나라도 FAIL이면 스크립트는 종료코드 `1`을 반환한다 (정상 종료 시 `0`).

## cron 등록 예시

매일 새벽 2시에 실행하고 실패 시에만 메일로 알림:

```cron
0 2 * * * /path/to/mapo_daily_check.sh > /tmp/daily_check/cron_last_run.log 2>&1 || echo "마포 일일점검 실패" | mail -s "[ALERT] mapo_daily_check FAIL" admin@example.com
```

## 에러 확인

mysqldump, pg_dumpall, tar 백업이 실패하면 아래 경로에 상세 에러가 남는다.

```bash
ls /tmp/daily_check/*.err
```

## 점검 항목

| 번호 | 항목 | 설명 |
|---|---|---|
| 1 | MariaDB 서비스 | `mariadbd` 프로세스 존재 여부 |
| 2 | Tomcat 서비스 | `apache-tomcat` 프로세스 존재 여부 |
| 3 | Tomcat 포트 | 8080 LISTEN 여부 |
| 4 | NetBox 포트 | 8000 LISTEN 여부 |
| 5 | MariaDB 백업 | `mysqldump --all-databases` 수행 및 결과 파일 확인 |
| 6 | Docker 서비스 | `systemctl is-active docker` |
| 7 | NetBox 컨테이너 | `docker ps`에 netbox 컨테이너 존재 여부 |
| 8 | PostgreSQL 백업 | NetBox postgres 컨테이너에서 `pg_dumpall` |
| 9 | NetBox Volume 백업 | media/reports/scripts/postgres-data 볼륨 tar 백업 |

## 주의사항

- `MYSQL_BACKUP_DIR`, `DOCKER_BACKUP_DIR`은 7일 지난 백업/로그 파일을 자동 삭제한다. 더 오래 보관해야 하면 스크립트 상단의 `RETENTION_DAYS` 값을 조정한다.
- NetBox PostgreSQL 컨테이너는 이름에 `netbox`와 `postgres`가 포함된 컨테이너를 자동으로 찾는다. 컨테이너가 여러 개 매칭되면 첫 번째 항목을 사용하므로, 멀티 인스턴스 환경에서는 `docker ps --format "{{.Names}}"`로 실제 이름을 확인 후 `NETBOX_PG_CONTAINER`를 스크립트 내에서 직접 지정하는 방식으로 전환 검토.
