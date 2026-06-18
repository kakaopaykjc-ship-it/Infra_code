#!/bin/bash

export LANG=C

TODAY=$(date +%Y%m%d)

LOG_DIR="/tmp/daily_check"
LOG_FILE="${LOG_DIR}/mapo_daily_check_${TODAY}.log"

MYSQL_BACKUP_DIR="/backup/mariadb"
DOCKER_BACKUP_DIR="/backup/docker"

mkdir -p ${LOG_DIR}
mkdir -p ${MYSQL_BACKUP_DIR}
mkdir -p ${DOCKER_BACKUP_DIR}

#########################################################
# 백업파일 정리 (7일 보관)
#########################################################

find ${MYSQL_BACKUP_DIR} -type f -name "*.sql" -mtime +7 -exec rm -f {} \;
find ${DOCKER_BACKUP_DIR} -type f -name "*.sql" -mtime +7 -exec rm -f {} \;
find ${DOCKER_BACKUP_DIR} -type f -name "*.tar.gz" -mtime +7 -exec rm -f {} \;

#########################################################
# 진행률 표시 함수
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

#########################################################
# 1. MariaDB 서비스 점검
#########################################################

show_progress "■□□□□□□□□□ 10% MariaDB 서비스 점검중..."

MARIADB_PROC=$(pgrep -f mariadbd | wc -l)

if [ "$MARIADB_PROC" -gt 0 ]; then
    LMS_DB_STATUS="OK"
else
    LMS_DB_STATUS="FAIL"
fi

#########################################################
# 2. Tomcat 서비스 점검
#########################################################

show_progress "■■□□□□□□□□ 20% Tomcat 서비스 점검중..."

TOMCAT_PROC=$(pgrep -f apache-tomcat | wc -l)

if [ "$TOMCAT_PROC" -gt 0 ]; then
    LMS_TOMCAT_STATUS="OK"
else
    LMS_TOMCAT_STATUS="FAIL"
fi

#########################################################
# 3. Tomcat 포트 점검
#########################################################

show_progress "■■■□□□□□□□ 30% Tomcat 8080 포트 점검중..."

TOMCAT_PORT=$(ss -antp | grep LISTEN | grep ':8080 ' | wc -l)

if [ "$TOMCAT_PORT" -gt 0 ]; then
    LMS_PORT_STATUS="OK"
else
    LMS_PORT_STATUS="FAIL"
fi

#########################################################
# 4. NetBox 8000 포트 점검
#########################################################

show_progress "■■■□□□□□□□ 35% NetBox 8000 포트 점검중..."

NETBOX_PORT=$(ss -lnt | awk '{print $4}' | grep -c ':8000$')

if [ "$NETBOX_PORT" -gt 0 ]; then
    NETBOX_PORT_STATUS="OK"
else
    NETBOX_PORT_STATUS="FAIL"
fi

#########################################################
# 5. MariaDB Dump 백업
#########################################################

show_progress "■■■■□□□□□□ 40% MariaDB Dump 백업 수행중..."

mysqldump \
-u root \
-proot \
--single-transaction \
--routines \
--events \
--all-databases \
> ${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql 2>/dev/null

if [ $? -eq 0 ]; then
    LMS_BACKUP_STATUS="OK"
else
    LMS_BACKUP_STATUS="FAIL"
fi

MYSQL_SIZE=$(du -sh ${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql 2>/dev/null | awk '{print $1}')

#########################################################
# 5. MariaDB Dump 확인
#########################################################

show_progress "■■■■■□□□□□ 50% MariaDB Dump 백업 확인중..."

if [ -s "${MYSQL_BACKUP_DIR}/mariadb_${TODAY}.sql" ]; then
    LMS_BACKUP_CHECK="OK"
else
    LMS_BACKUP_CHECK="FAIL"
fi

#########################################################
# 6. Docker 서비스 점검
#########################################################

show_progress "■■■■■■□□□□ 60% Docker 서비스 점검중..."

DOCKER_SERVICE=$(systemctl is-active docker 2>/dev/null)

if [ "$DOCKER_SERVICE" = "active" ]; then
    DOCKER_STATUS="OK"
else
    DOCKER_STATUS="FAIL"
fi

#########################################################
# 7. NetBox 컨테이너 점검
#########################################################

show_progress "■■■■■■■□□□ 70% NetBox 컨테이너 점검중..."

NETBOX_COUNT=$(docker ps --format "{{.Names}}" | grep -i netbox | wc -l)

if [ "$NETBOX_COUNT" -gt 0 ]; then
    NETBOX_STATUS="OK"
else
    NETBOX_STATUS="FAIL"
fi

#########################################################
# 8. PostgreSQL Dump 백업
#########################################################

show_progress "■■■■■■■■□□ 80% NetBox PostgreSQL 백업중..."

docker exec netbox-docker-postgres-1 \
pg_dumpall -U netbox \
> ${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql

if [ $? -eq 0 ]; then
    NETBOX_DB_BACKUP="OK"
else
    NETBOX_DB_BACKUP="FAIL"
fi

PG_SIZE=$(du -sh ${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql 2>/dev/null | awk '{print $1}')

#########################################################
# 9. PostgreSQL Dump 확인
#########################################################

show_progress "■■■■■■■■■□ 90% NetBox PostgreSQL 백업 확인중..."

if [ -s "${DOCKER_BACKUP_DIR}/netbox_db_${TODAY}.sql" ]; then
    NETBOX_DB_CHECK="OK"
else
    NETBOX_DB_CHECK="FAIL"
fi

#########################################################
# 10. NetBox Volume 백업
#########################################################

show_progress "■■■■■■■■■■ 95% NetBox Volume 백업중..."

tar czf ${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz \
/var/lib/docker/volumes/netbox-docker_netbox-media-files \
/var/lib/docker/volumes/netbox-docker_netbox-reports-files \
/var/lib/docker/volumes/netbox-docker_netbox-scripts-files \
/var/lib/docker/volumes/netbox-docker_netbox-postgres-data \
>/dev/null 2>&1

if [ $? -eq 0 ]; then
    NETBOX_VOL_BACKUP="OK"
else
    NETBOX_VOL_BACKUP="FAIL"
fi

VOL_SIZE=$(du -sh ${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz 2>/dev/null | awk '{print $1}')

#########################################################
# 11. NetBox Volume 확인
#########################################################

show_progress "■■■■■■■■■■ 99% NetBox Volume 백업 확인중..."

if [ -s "${DOCKER_BACKUP_DIR}/netbox_volume_${TODAY}.tar.gz" ]; then
    NETBOX_VOL_CHECK="OK"
else
    NETBOX_VOL_CHECK="FAIL"
fi

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
echo "   백업파일 크기                    : ${MYSQL_SIZE}"

echo ""
echo "==================== NetBox 점검 결과 ===================="
echo "6. Docker 서비스 상태               : ${DOCKER_STATUS}"
echo "7. NetBox 컨테이너 상태             : ${NETBOX_STATUS}"
echo "8. NetBox 포트 상태(8000)           : ${NETBOX_PORT_STATUS}"
echo "9. NetBox PostgreSQL Dump 백업      : ${NETBOX_DB_BACKUP}"
echo "10. NetBox PostgreSQL Dump 확인     : ${NETBOX_DB_CHECK}"
echo "    백업파일 크기                   : ${PG_SIZE}"
echo "11. NetBox Volume 백업              : ${NETBOX_VOL_BACKUP}"
echo "12. NetBox Volume 백업 확인         : ${NETBOX_VOL_CHECK}"
echo "    백업파일 크기                   : ${VOL_SIZE}"

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
echo "MariaDB Backup Size        : ${MYSQL_SIZE}"
echo "Docker Service             : ${DOCKER_STATUS}"
echo "NetBox Container           : ${NETBOX_STATUS}"
echo "NetBox PostgreSQL Backup   : ${NETBOX_DB_BACKUP}"
echo "NetBox PostgreSQL Check    : ${NETBOX_DB_CHECK}"
echo "NetBox PostgreSQL Size     : ${PG_SIZE}"
echo "NetBox Volume Backup       : ${NETBOX_VOL_BACKUP}"
echo "NetBox Volume Check        : ${NETBOX_VOL_CHECK}"
echo "NetBox Volume Size         : ${VOL_SIZE}"
echo "=================================================================="
} >> ${LOG_FILE}

echo ""
echo "로그파일 : ${LOG_FILE}"