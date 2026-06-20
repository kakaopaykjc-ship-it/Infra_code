#!/bin/bash
#
# 마포구청 LMS / NetBox 일일점검 스크립트
# 사용법은 README_mapo_daily_check.md 참고
#
set -uo pipefail
export LANG=C

TODAY=$(date +%Y%m%d)

LOG_DIR="/tmp/daily_check"
LOG_FILE="${LOG_DIR}/mapo_daily_check_${TODAY}.log"
LOCK_FILE="/tmp/mapo_daily_check.lock"

MYSQL_BACKUP_DIR="/backup/mariadb"
DOCKER_BACKUP_DIR="/backup/docker"
RETENTION_DAYS=7

# MySQL 인증 정보: 환경변수로 주입하거나 ~/.my.cnf 사용을 권장한다.
# 인라인 비밀번호 하드코딩은 ps 출력/히스토리에 노출되므로 사용하지 않는다.
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-$HOME/.my.cnf}"

NETBOX_PG_USER="${NETBOX_PG_USER:-netbox}"

# 중복 실행 방지
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    echo "[ERROR] 이미 실행 중인 점검 프로세스가 있습니다. (lock: ${LOCK_FILE})" >&2
    exit 1
fi

mkdir -p "${LOG_DIR}" "${MYSQL_BACKUP_DIR}" "${DOCKER_BACKUP_DIR}"

OVERALL_RESULT=0

#########################################################
# 백업파일 / 로그 정리 (지정 일수 보관)
#########################################################

find "${MYSQL_BACKUP_DIR}" -type f -name "*.sql" -mtime "+${RETENTION_DAYS}" -delete
find "${DOCKER_BACKUP_DIR}" -type f -name "*.sql" -mtime "+${RETENTION_DAYS}" -delete
find "${DOCKER_BACKUP_DIR}" -type f -name "*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete
find "${LOG_DIR}" -type f -name "mapo_daily_check_*.log" -mtime "+${RETENTION_DAYS}" -delete

#########################################################
# 공통 함수
#########################################################

show_progress() {
    clear
    echo ""
    echo "=============================================================="
    echo "         마포구청 LMS / NetBox 일일점검 진행상황"
    echo "=============================================================="
    echo ""
    echo "$1"
    echo ""
}

# 명령 종료코드를 점검 결과(OK/FAIL)로 변환하고, FAIL이면 전체 결과 플래그를 세운다.
check_status() {
    local rc="$1"
    if [ "$rc" -eq 0 ]; then
        echo "OK"
    else
        OVERALL_RESULT=1
        echo "FAIL"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

#########################################################
# 1. MariaDB 서비스 점검
#########################################################

show_progress "■□□□□□□□□□ 10% MariaDB 서비스 점검중..."

MARIADB_PROC=$(pgrep -c -f mariadbd || true)
LMS_DB_STATUS=$(check_status $([ "${MARIADB_PROC:-0}" -gt 0 ]; echo $?))

#########################################################
# 2. Tomcat 서비스 점검
#########################################################

show_progress "■■□□□□□□□□ 20% Tomcat 서비스 점검중..."

TOMCAT_PROC=$(pgrep -c -f apache-tomcat || true)
LMS_TOMCAT_STATUS=$(check_status $([ "${TOMCAT_PROC:-0}" -gt 0 ]; echo $?))

#########################################################
# 3. Tomcat 포트 점검
#########################################################

show_progress "■■■□□□□□□□ 30% Tomcat 8080 포트 점검중..."

TOMCAT_PORT=$(ss -antp 2>/dev/null | grep -c "LISTEN.*:8080 " || true)
LMS_PORT_STATUS=$(check_status $([ "${TOMCAT_PORT:-0}" -gt 0 ]; echo $?))

#########################################################
# 4. NetBox 8000 포트 점검
#########################################################

show_progress "■■■□□□□□□□ 35% NetBox 8000 포트 점검중..."

NETBOX_PORT=$(ss -lnt 2>/dev/null | awk '{print $4}' | grep -c ':8000$' || true)
NETBOX_PORT_STATUS=$(check_status $([ "${NETBOX_PORT:-0}" -gt 0 ]; echo $?))

#########################################################
# 5. MariaDB Dump 백업
#########################################################

show_progress "■■■■□□□□□□ 40% MariaDB Dump 백업 수행중..."

MYSQL_DUMP_ERR="${LOG_DIR}/mysqldump_${TODAY}.err"
MYSQLDUMP_ARGS=(--single-transaction --routines --events --all-databases)
if [ -f "${MYSQL_DEFAULTS_FILE}" ]; then
    MYSQLDUMP_ARGS=(--defaults-extra-file="${MYSQL_DEFAULTS_FILE}" -u "${MYSQL_USER}" "${MYSQLDUMP_ARGS[@]}")
else
    MYSQLDUMP_ARGS=(-u "${MYSQL_USER}" "${MYSQLDUMP_ARGS[@]}")
fi

mysqldump "${MYSQLDUMP_ARGS[@]}" > "${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql" 2>"${MYSQL_DUMP_ERR}"
LMS_BACKUP_STATUS=$(check_status $?)

MYSQL_SIZE=$(du -sh "${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql" 2>/dev/null | awk '{print $1}')

#########################################################
# 5. MariaDB Dump 확인
#########################################################

show_progress "■■■■■□□□□□ 50% MariaDB Dump 백업 확인중..."

LMS_BACKUP_CHECK=$(check_status $([ -s "${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql" ]; echo $?))

#########################################################
# 6. Docker 서비스 점검
#########################################################

show_progress "■■■■■■□□□□ 60% Docker 서비스 점검중..."

DOCKER_SERVICE=$(systemctl is-active docker 2>/dev/null || true)
DOCKER_STATUS=$(check_status $([ "${DOCKER_SERVICE}" = "active" ]; echo $?))

#########################################################
# 7. NetBox 컨테이너 점검
#########################################################

show_progress "■■■■■■■□□□ 70% NetBox 컨테이너 점검중..."

NETBOX_COUNT=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -ci netbox || true)
NETBOX_STATUS=$(check_status $([ "${NETBOX_COUNT:-0}" -gt 0 ]; echo $?))

# postgres 컨테이너명을 하드코딩하지 않고 실행 중인 컨테이너에서 탐색한다.
NETBOX_PG_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i 'netbox.*postgres' | head -n1 || true)

#########################################################
# 8. PostgreSQL Dump 백업
#########################################################

show_progress "■■■■■■■■□□ 80% NetBox PostgreSQL 백업중..."

if [ -n "${NETBOX_PG_CONTAINER}" ]; then
    docker exec "${NETBOX_PG_CONTAINER}" pg_dumpall -U "${NETBOX_PG_USER}" \
        > "${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql" \
        2>"${LOG_DIR}/pg_dumpall_${TODAY}.err"
    NETBOX_DB_BACKUP=$(check_status $?)
else
    echo "[ERROR] NetBox PostgreSQL 컨테이너를 찾을 수 없습니다." >&2
    NETBOX_DB_BACKUP="FAIL"
    OVERALL_RESULT=1
fi

PG_SIZE=$(du -sh "${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql" 2>/dev/null | awk '{print $1}')

#########################################################
# 9. PostgreSQL Dump 확인
#########################################################

show_progress "■■■■■■■■■□ 90% NetBox PostgreSQL 백업 확인중..."

NETBOX_DB_CHECK=$(check_status $([ -s "${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql" ]; echo $?))

#########################################################
# 10. NetBox Volume 백업
#########################################################

show_progress "■■■■■■■■■■ 95% NetBox Volume 백업중..."

NETBOX_VOLUMES=(
    /var/lib/docker/volumes/netbox-docker_netbox-media-files
    /var/lib/docker/volumes/netbox-docker_netbox-reports-files
    /var/lib/docker/volumes/netbox-docker_netbox-scripts-files
    /var/lib/docker/volumes/netbox-docker_netbox-postgres-data
)

tar czf "${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz" \
    "${NETBOX_VOLUMES[@]}" \
    >"${LOG_DIR}/tar_${TODAY}.err" 2>&1
NETBOX_VOL_BACKUP=$(check_status $?)

VOL_SIZE=$(du -sh "${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz" 2>/dev/null | awk '{print $1}')

#########################################################
# 11. NetBox Volume 확인
#########################################################

show_progress "■■■■■■■■■■ 99% NetBox Volume 백업 확인중..."

NETBOX_VOL_CHECK=$(check_status $([ -s "${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz" ]; echo $?))

#########################################################
# 완료
#########################################################

show_progress "■■■■■■■■■■ 100% 점검 완료"
sleep 1

#########################################################
# 결과 출력
#########################################################

clear

echo "=================================================================="
echo "              마포구청 LMS / NetBox 일일점검 결과"
echo "=================================================================="
echo "점검일시 : $(date)"
echo "=================================================================="

echo "====================== LMS 점검 결과 ======================"
echo "1. MariaDB 서비스 상태              : ${LMS_DB_STATUS}"
echo "2. Tomcat 서비스 상태               : ${LMS_TOMCAT_STATUS}"
echo "3. Tomcat 포트 상태(8080)           : ${LMS_PORT_STATUS}"
echo "4. MariaDB Dump 백업                : ${LMS_BACKUP_STATUS}"
echo "5. MariaDB Dump 백업 확인           : ${LMS_BACKUP_CHECK}"
echo "   백업파일 크기                    : ${MYSQL_SIZE:-N/A}"

echo ""
echo "==================== NetBox 점검 결과 ===================="
echo "6. Docker 서비스 상태               : ${DOCKER_STATUS}"
echo "7. NetBox 컨테이너 상태             : ${NETBOX_STATUS}"
echo "8. NetBox 포트 상태(8000)           : ${NETBOX_PORT_STATUS}"
echo "9. NetBox PostgreSQL Dump 백업      : ${NETBOX_DB_BACKUP}"
echo "10. NetBox PostgreSQL Dump 확인     : ${NETBOX_DB_CHECK}"
echo "    백업파일 크기                   : ${PG_SIZE:-N/A}"
echo "11. NetBox Volume 백업              : ${NETBOX_VOL_BACKUP}"
echo "12. NetBox Volume 백업 확인         : ${NETBOX_VOL_CHECK}"
echo "    백업파일 크기                   : ${VOL_SIZE:-N/A}"

echo "=================================================================="
if [ "${OVERALL_RESULT}" -eq 0 ]; then
    echo "전체 결과 : OK"
else
    echo "전체 결과 : FAIL (상세 내용은 ${LOG_DIR}/*.err 파일 참고)"
fi
echo "=================================================================="

{
echo "=================================================================="
echo "점검일시 : $(date)"
echo "=================================================================="
echo "MariaDB Service            : ${LMS_DB_STATUS}"
echo "Tomcat Service             : ${LMS_TOMCAT_STATUS}"
echo "Tomcat Port                : ${LMS_PORT_STATUS}"
echo "MariaDB Backup             : ${LMS_BACKUP_STATUS}"
echo "MariaDB Backup Check       : ${LMS_BACKUP_CHECK}"
echo "MariaDB Backup Size        : ${MYSQL_SIZE:-N/A}"
echo "Docker Service             : ${DOCKER_STATUS}"
echo "NetBox Container           : ${NETBOX_STATUS}"
echo "NetBox Port                : ${NETBOX_PORT_STATUS}"
echo "NetBox PostgreSQL Backup   : ${NETBOX_DB_BACKUP}"
echo "NetBox PostgreSQL Check    : ${NETBOX_DB_CHECK}"
echo "NetBox PostgreSQL Size     : ${PG_SIZE:-N/A}"
echo "NetBox Volume Backup       : ${NETBOX_VOL_BACKUP}"
echo "NetBox Volume Check        : ${NETBOX_VOL_CHECK}"
echo "NetBox Volume Size         : ${VOL_SIZE:-N/A}"
echo "Overall Result             : $([ "${OVERALL_RESULT}" -eq 0 ] && echo OK || echo FAIL)"
echo "=================================================================="
} >> "${LOG_FILE}"

echo ""
echo "로그파일 : ${LOG_FILE}"

exit "${OVERALL_RESULT}"
