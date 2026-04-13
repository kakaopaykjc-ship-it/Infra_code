#!/bin/bash
# --------------------------------------------------------------------------------
# 스크립트 명: Unix/Linux 취약점 점검 스크립트 (최종 통합본)
# 작성일: 2026-01-12
# --------------------------------------------------------------------------------

# ult "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "$${DETAILS[$CODE]}". 변수 설정
RESULT_FILE="vuln_check_result_$(date +%Y%m%d).txt"

GOOD_CNT=0
VULN_CNT=0
CHECK_CNT=0
TOTAL_CNT=0

declare -A RESULTS # 결과 배열
declare -A DETAILS # 상세내용 배열
declare -A NAMES # 항목 이름 배열
declare -A VULN_UNIT # 취약 항목 배열
declare -A CHECK_UNIT # 체크 필요 항목 배열

#실행 리스트 생성. {1..N} 으로 최대값 지정
CHECK_LIST=($(printf "U_%02d " {1..67}))

# 결과 파일 초기화
echo "[주요정보통신기반시설 Unix/Linux 서버 취약점 점검 결과]" > "$RESULT_FILE"
echo "점검 일시: $(date)" >> "$RESULT_FILE"
echo -e "--------------------------------------------------------\n" >> "$RESULT_FILE"

# 결과 출력 및 카운트 함수

print_result() {
	local CODE=$1
	local NAME=$2
	local RES=$3
	local DET=$4

	case "$RES" in
		"양호")
			((GOOD_CNT++))
			;;
		"취약")
			((VULN_CNT++))
			VULN_UNIT[$CODE]=$CODE
			;;
		"체크필요")
			((CHECK_CNT++))
			CHECK_UNIT[$CODE]=$CODE
			;;
		*)
			echo "[$CODE] : 결과값 오류 : $RES"
			return
			;;
	esac

	((TOTAL_CNT++))

	{
		echo -e "[$CODE] $NAME"
		echo -e "결과 : $RES"
		echo -e "상세내용: $DET"
		echo -e "---------------------------------------------------------\n"
	} >> "$RESULT_FILE"

	echo -e "[$CODE] 점검 완료 -> $RES"
}







#--------------------------------------------------------------------------------
# U_01. root 계정 원격 접속 제한
#--------------------------------------------------------------------------------


U_01() {
	local CODE="U_01"
	NAMES[$CODE]="root 계정 원격 접속 제한"

	if [ -f /etc/ssh/sshd_config ]; then
		ROOT_LOGIN=$(grep -vi "^#" /etc/ssh/sshd_config | grep -i "PermitRootLogin" | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
		if [ "$ROOT_LOGIN" == "no" ]; then
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="루트 로그인제한 확인"
		else
			RESULTS[$CODE]="취약"
			DETAILS[$CODE]="루트 로그인제한되지 않음"
		fi
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="sshd_config 파일이 없습니다."
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


#--------------------------------------------------------------------------------
# U_02. 패스워드 복잡성과 정책 설정
#--------------------------------------------------------------------------------

U_02() {
	local CODE="U_02"
	NAMES[$CODE]="패스워드 복잡성 및 정책 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	local AGE_CHECK=0
	local COMPLEX_CHECK=0
	local HISTORY_CHECK=0

	# --- Step 1: 기간 설정 점검 (/etc/login.defs) ---
	if [ -f /etc/login.defs ]; then
		local MAX_DAYS=$(grep -v "^#" /etc/login.defs | grep "PASS_MAX_DAYS" | awk '{print $2}')
		local MIN_DAYS=$(grep -v "^#" /etc/login.defs | grep "PASS_MIN_DAYS" | awk '{print $2}')

		if [[ -n "$MAX_DAYS" && "$MAX_DAYS" -le 90 && -n "$MIN_DAYS" && "$MIN_DAYS" -ge 1 ]]; then
			AGE_CHECK=1
			DETAILS[$CODE]+="[기간:양호(Max:$MAX_DAYS,Min:$MIN_DAYS)]"
		else
			DETAILS[$CODE]+="[기간:미흡] "
		fi
	else
		DETAILS[$CODE]+="[기간:login.defs파일없음] "
	fi

	# --- Step 2: 복잡성 설정 점검 ---
	if [ -f /etc/security/pwquality.conf ]; then
		local PQ_MINLEN=$(grep -v "^#" /etc/security/pwquality.conf | grep "minlen" | awk -F= '{print $2}' | tr -d ' ')
		if [[ -n "$PQ_MINLEN" && "$PQ_MINLEN" -ge 8 ]]; then
			COMPLEX_CHECK=1
			DETAILS[$CODE]+="[복잡성:pwquality양호] "
		fi
	fi
	# 만약 위에서 체크가 안 됐다면 PAM 파일 직접 확인
	if [ $COMPLEX_CHECK -eq 0 ]; then
		if [ -f /etc/pam.d/system-auth ] && grep -q "pam_pwquality.so" /etc/pam.d/system-auth; then
			COMPLEX_CHECK=1
			DETAILS[$CODE]+="[복잡성:PAM모듈확인됨] "
		else
			DETAILS[$CODE]+="[복잡성:미흡] "
		fi
	fi

	# --- Step 3: 재사용 방지 점검 ---
	local HISTORY_CHECK=0
	local THRESHOLD=5

	#/etc/security/pwhistory.conf 확인 (Rocky 8, 9 위주)
	if [ -f /etc/security/pwhistory.conf ]; then
   		local CONF_REM=$(grep -E "^\s*remember\s*=" /etc/security/pwhistory.conf | awk -F'=' '{print $2}' | tr -d ' ')
   		if [[ -n "$CONF_REM" && "$CONF_REM" -ge $THRESHOLD ]]; then
        	HISTORY_CHECK=1
    	fi
	fi

	#PAM 파일 직접 확인 (Rocky 7 및 전체 공통)
	# system-auth와 password-auth에서 pam_pwhistory.so 또는 pam_unix.so의 remember 설정 확인
	local PAM_FILES=("/etc/pam.d/system-auth" "/etc/pam.d/password-auth")
	for PAM_FILE in "${PAM_FILES[@]}"; do
    	if [ -f "$PAM_FILE" ]; then
       		# 주석 제외하고 remember 설정값 추출
        	local PAM_REM=$(grep -v "^#" "$PAM_FILE" | grep -E "pam_(pwhistory|unix)\.so" | grep -oE "remember=[0-9]+" | cut -d'=' -f2)
        
        	# 값이 존재하고 기준치 이상인지 확인
        	for VAL in $PAM_REM; do
            	if [[ -n "$VAL" && "$VAL" -ge $THRESHOLD ]]; then
                	HISTORY_CHECK=1
            	fi
        	done
    	fi
	done

# 최종 결과 저장
	if [ "$HISTORY_CHECK" -eq 1 ]; then
  		DETAILS[$CODE]+="[재사용:양호(remember >= $THRESHOLD)] "
	else
   		DETAILS[$CODE]+="[재사용:취약(설정 미비 또는 기준 미달)] "
   		VULN_FOUND=1
	fi

	# --- 최종 판정: 3가지 모두 통과해야 양호 ---
	if [[ $AGE_CHECK -eq 1 && $COMPLEX_CHECK -eq 1 && $HISTORY_CHECK -eq 1 ]]; then
		RESULTS[$CODE]="양호"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}








# --------------------------------------------------------------------------------
# U_03. 계정 잠금 임계값 설정 (RHEL 7/8/9 통합)
# --------------------------------------------------------------------------------
U_03() {
	local CODE="U_03"
	NAMES[$CODE]="계정 잠금 임계값 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# 1. RHEL 8/9 faillock.conf 확인
	if [ -f /etc/security/faillock.conf ]; then
		DENY_VAL=$(grep -vi "^#" /etc/security/faillock.conf | grep "deny" | awk -F'=' '{print $2}' | xargs)
		if [ ! -z "$DENY_VAL" ]; then
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="[RHEL 8/9] faillock.conf deny=$DENY_VAL 설정됨"
		fi
	fi

	# 2. 결과가 아직 취약이면 PAM 파일 직접 확인 (RHEL 7 tally2 포함)
	if [ "${RESULTS[$CODE]}" == "취약" ]; then
		for PAM_FILE in /etc/pam.d/system-auth /etc/pam.d/password-auth; do
			if [ -f "$PAM_FILE" ]; then
				if grep -vi "^#" "$PAM_FILE" | grep -q "pam_tally2.so"; then
					RESULTS[$CODE]="양호"
					DETAILS[$CODE]="[RHEL 7] $PAM_FILE 에서 pam_tally2 발견"
					break
				elif grep -vi "^#" "$PAM_FILE" | grep -q "pam_faillock.so"; then
					RESULTS[$CODE]="양호"
					DETAILS[$CODE]="[RHEL 8/9] $PAM_FILE 에서 pam_faillock 발견"
					break
				fi
			fi
		done
	fi
	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_04. 비밀번호 파일 보호
# --------------------------------------------------------------------------------

U_04() {
	local CODE="U_04"
	NAMES[$CODE]="비밀번호 파일 보호"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# /etc/passwd 의 2번째 필드가 x가 아닌 유저 찾기
	NO_X_USERS=$(grep -v "^#" /etc/passwd | awk -F: '$2 != "x" {print $1}')

	if [ -z "$NO_X_USERS" ]; then
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="암호화 O"

	else
		RESULTS[$CODE]="취약"
		DETAILS[$CODE]="암호화 안되어있음. $NO_X_USERS "
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_05. root 이외 UID "0" 금지
# --------------------------------------------------------------------------------

U_05() {
	local CODE="U_05"
	NAMES[$CODE]="ROOT 이외 UID 값 0 금지"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# /etc/passwd 의 3번째 필드가 0인 유저 찾기
	UID0_USERS=$(grep -v "^#" /etc/passwd | awk -F: '($3 == 0) && ($1 != "root") {print $1}')

	if [ -z "$UID0_USERS" ]; then
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="root 계정 외 UID 0 없음"
	else
		DETAILS[$CODE]="root 외 UID 0 USER : $UID0_USERS "
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}


# --------------------------------------------------------------------------------
# U_06. 사용자 계정 su 기능 제한
# --------------------------------------------------------------------------------

U_06() {
	local CODE="U_06"
	NAMES[$CODE]="사용자 계정 su 제한"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	PAM_FILE="/etc/pam.d/su"
	SU_BIN="/usr/bin/su"

	#STEP 1 - PAM 설정 확인 (pam_wheel.so 모듈 활성화)
	PAM_CHECK=$(grep -v "^#" /etc/pam.d/su | grep "pam_wheel.so")


	#STEP 2 - /etc/group 파일 내 wheel 그룹 확인
	WHEEL_USERS=$(grep -v "^#" /etc/group | awk -F: '($1 == "wheel") {print $4}')

	# 판별

	if [ -n "$PAM_CHECK" ]; then
		if [ -n "$WHEEL_USERS" ]; then
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="PAM 모듈 적용,wheel 그룹 사용중, wheel 그룹 사용자 : "$WHEEL_USERS""
		else
			#WHEEL 그룹 빈 경우 -> PAM.D 에서 직접 지정한건지 확인

			DIRECT_CHECK=$(grep -E "^\s*auth\s+required\s+pam_wheel.so" $PAM_FILE | grep -E "use_uid|group=")
			if [ -n "$DIRECT_CHECK" ]; then
				RESULTS[$CODE]="양호"
				DETAILS[$CODE]="wheel group user는 없으나 pam.d에서 직접 지정"

			else
				RESULTS[$CODE]="체크필요"
				DETAILS[$CODE]="wheel 모듈 사용, 그룹 없음, pam.d 직접 지정 없음. sudo 사용자 있는지 확인 필요"
			fi
		fi

	else
		DETAILS[$CODE]="pam_wheel.so 적용 안되어있음"

	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}

# --------------------------------------------------------------------------------
# U_07. 불필요 계정 제거
# --------------------------------------------------------------------------------

U_07() {
	local CODE="U_07"
	NAMES[$CODE]="불필요 계정 제거"
	RESULTS[$CODE]="체크필요"
	DETAILS[$CODE]="불필요 계정 제거 확인 필요"

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_08. root 그룹 확인
# --------------------------------------------------------------------------------

U_08() {
	local CODE="U_08"
	NAMES[$CODE]="root 그룹 확인"
	RESULTS[$CODE]="체크필요"

	# root 그룹 사용자 목록 확인
	GROUPCHECK=$(grep -v "^#" /etc/group | grep "root" | awk -F: '{print $4}')
	DETAILS[$CODE]="root 그룹 확인 필요, root 그룹 사용자 : "$GROUPCHECK""

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_09. 동일 gid 금지
# --------------------------------------------------------------------------------

U_09(){

	local CODE="U_09"
	NAMES[$CODE]="동일 gid 금지"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# 동일 gid 검사

	DUPLICATE_GID=$(cut -d: -f3 /etc/group | sort | uniq -d)

	if [ -n "$DUPLICATE_GID" ]; then
		DETAILS[$CODE]="중복된 GID 및 그룹 목록 :"


		for gid in $DUPLICATE_GID; do
			USER_LIST=$(awk -F: -v gid="$gid" '$3 == gid {print $1}' /etc/group | xargs | sed 's/ /, /g')
			DETAILS[$CODE]="$${DETAILS[$CODE]} [GID:$gid -> 계정 : $USER_LIST]"
		done

	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="중복 GID 계정 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_.10 동일 uid 금지
# --------------------------------------------------------------------------------
U_10() {
	local CODE="U_10"
	NAMES[$CODE]="동일 uid 금지"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# 동일 uid 검사

	DUPLICATE_UID=$(cut -d: -f3 /etc/passwd | sort | uniq -d)

	if [ -n "$DUPLICATE_UID" ]; then
		DETAILS[$CODE]="중복된 UID 및 그룹 목록 :"

		for uid in $DUPLICATE_UID; do
			USER_LIST=$(awk -F: -v uid="$uid" '$3 == uid {print $1}' /etc/passwd | xargs | sed 's/ /, /g')
			DETAILS[$CODE]="$${DETAILS[$CODE]} [UID:$uid -> 계정 : $USER_LIST]"

		done

	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="중복 UID 계정 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_11. 사용자 shell 점검
# --------------------------------------------------------------------------------
U_11() {
	local CODE="U_11"
	NAMES[$CODE]="사용자 shell 점검"
	RESULTS[$CODE]="체크필요"
	DETAILS[$CODE]=""

	#/sbin/nologin , /bin/false 이 아닌 셸 사용자

	BASH_USERS=$(grep -Ev "/sbin/nologin|/bin/false" /etc/passwd | cut -d: -f1 | xargs | sed 's/ /, /g')

	DETAILS[$CODE]="다음 사용자 확인 필요 - "$BASH_USERS""

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}

# --------------------------------------------------------------------------------
# U_12. 세션 타임아웃 설정
# --------------------------------------------------------------------------------


U_12(){
	local CODE="U_12"
	NAMES[$CODE]="세션 타임아웃 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	#/etc/profile 에 TMOUT 설정값 가져오기

	TMOUT_VAL=$(grep -i "TMOUT=" /etc/profile | grep -v "^#" | tail -1 | cut -d= -f2)

	#export TMOUT 있는지 확인

	EXPORT_CHECK=$(grep -i "export TMOUT" /etc/profile | grep -v "^#")

	#판별

	if [ -z "$TMOUT_VAL" ]; then
		DETAILS[$CODE]="TMOUT 값이 없습니다"
	elif [ -z "$EXPORT_CHECK" ]; then
		DETAILS[$CODE]="export TMOUT 설정이 없습니다."
	else
		if [ "$TMOUT_VAL" -le 600 ] && [ "$TMOUT_VAL" -ne 0 ]; then
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="export TMOUT 설정 완료 및 TMOUT 값 600초 이하"
		elif [ "$TMOUT_VAL" -eq 0 ]; then
			DETAILS[$CODE]="TMOUT 이0(무제한) 입니다."
		else
			DETAILS[$CODE]="TMOUT 이 600초를 넘습니다."
		fi
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}

# --------------------------------------------------------------------------------
# U_.13 암호화 알고리즘 체크
# --------------------------------------------------------------------------------

U_13(){
	local CODE="U_13"
	NAMES[$CODE]="암호화 알고리즘 체크"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	#/etc/login.defs 의 CRYPT_DEFAULT 확인
	CRYPT_VAL=$(grep -Ei "ENCRYPT_METHOD" /etc/login.defs | grep -v "^#" | awk '{print $2}')

	if [ -n "$CRYPT_VAL" ]; then
		if [ "$CRYPT_VAL" = "SHA256" ] || [ "$CRYPT_VAL" = "SHA512" ]; then
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]=" 암호화 사용중 ( "$CRYPT_VAL" )"
		else
			DETAILS[$CODE]="SHA256, SHA512 가 아닙니다."
		fi
	else
		DETAILS[$CODE]="암호화 설정이 없습니다."
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_.14 환경변수 마침표 체크
# --------------------------------------------------------------------------------

U_14(){

	local CODE="U_14"
	NAMES[$CODE]="환경변수 마침표 체크"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	if echo "$PATH" | grep -qE "(^|:)[^/]"; then
		DETAILS[$CODE]="PATH 환경변수에 비정상 경로 발견 (현 PATH=$PATH)"
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="모든 PATH 경로가 절대경로로 설정됨"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_.15 파일 및 디렉터리 소유자 설정
# --------------------------------------------------------------------------------

U_15(){
	local CODE="U_15"
	NAMES[$CODE]="파일 및 디렉터리 소유자 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	NO_OWN=$(find / \(-nouser -o -nogroup\) -xdev -ls 2>/dev/null)

	if [ -n "$NO_OWN" ]; then
		DETAILS[$CODE]="그룹 혹은 소유자가 없는 파일 목록 : "$NO_OWN""

	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="그룹 혹은 소유자 없는 파일 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}

# --------------------------------------------------------------------------------
# U_16. /etc/passwd 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------
U_16(){
	local CODE="U_16"
	NAMES[$CODE]="/etc/passwd 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""


	if [ -f /etc/passwd ]; then
		PERM=$(stat -c "%A" /etc/passwd | cut -c5-10)
		PASSWDOWN=$(stat -c "%U" /etc/passwd)

		if $(echo "$PERM" | grep -qE "w|x") || [ $PASSWDOWN != "root" ]; then
			DETAILS[$CODE]="소유자 혹은 권한 확인 필요, 소유자 : "$PASSWDOWN" , 권한 : $(stat -c "%A" /etc/passwd)"
		else
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="권한 및 소유자 상태 양호."
		fi
	else
		DETAILS[$CODE]="파일이 없습니다."
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_17. 시스템 시작 스크립트 권한 설정
# --------------------------------------------------------------------------------

U_17(){

	local CODE="U_17"
	NAMES[$CODE]="시스템 시작 스크립트 권한 설정"
	RESULTS[$CODE]="양호"
	DETAILS[$CODE]=""

	# 심볼릭 링크들 원본 확인
	TARGET_FILES=$(readlink -f /etc/systemd/system/* 2>/dev/null)
	VULN_LIST=""

	for file in $TARGET_FILES; do
		if [ -f "$file" ]; then
			OWNER=$(stat -c "%U" "$file")
			PERM=$(stat -c "%a" "$file")
			#소유자 권한과 그룹,사용자 권한 따로 체크
			USER_PERM=$(stat -c "%A" "$file" | cut -c5-10)
			OWN_PERM=$(stat -c "%a" "$file" | cut -c1)

			#판별

			if [ "$OWNER" != "root" ] || [ "$OWN_PERM" -gt 6 ] || echo "$USER_PERM" | grep -qE "w"; then
				VULN_LIST="$VULN_LIST"$'\n'"- $file ( 소유자: $OWNER, 권한 : $PERM )"
				RESULTS[$CODE]="취약"
			fi
		fi
	done

	if [ "${RESULTS[$CODE]}" = "양호" ]; then
		DETAILS[$CODE]="모든 시작 스크립트 권한과 소유자가 양호"
	else
		DETAILS[$CODE]="권한과 소유자 이상 있는 파일 : $VULN_LIST"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_18. /etc/shadow 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_18(){
	local CODE="U_18"
	NAMES[$CODE]="/etc/shadow 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	OWNER=$(stat -c "%U" /etc/shadow)
	#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2
	P1=$(stat -c "%A" /etc/shadow | cut -c2-4)
	P2=$(stat -c "%A" /etc/shadow | cut -c5-10)

	if echo $P2 | grep -qE "r|w|x" || echo $P1 | grep -qE "w|x" | [ "$OWNER" != "root" ]; then
		DETAILS[$CODE]=" 소유자 혹은 권한에 이상. /etc/shadow 소유자 : "$OWNER", 권한 : "$P1""$P2""
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="/etc/shadow 파일 권한/소유자 양호"
	fi


	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_19. /etc/hosts 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_19(){
	local CODE="U_19"
	NAMES[$CODE]="/etc/hosts 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2
	if [ -f "/etc/hosts" ]; then
		OWNER=$(stat -c "%U" /etc/hosts)
		#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2
		P1=$(stat -c "%a" /etc/hosts | cut -c1)
		P2=$(stat -c "%A" /etc/hosts | cut -c5-10)

		if [ $P1 -gt 6 ] || echo $P2 | grep -qE "w|x"; then
			DETAILS[$CODE]="소유자 혹은 권한 취약. 소유자 : $OWNER, 권한 : $(stat -c "%a" /etc/hosts)"
		else
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="소유자 , 권한 모두 양호"
		fi

	else
		DETAILS[$CODE]="파일이 없습니다."
	fi


	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_20. /etc/(x)inetd.conf 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_20(){
	local CODE="U_20"
	NAMES[$CODE]="/etc/(x)inetd.conf 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""



	#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2

	local FILEPATH=("/etc/xinetd" "/etc/inetd")
	local FOUND=0

	for FILE in "{$FILEPATH[@]}"; do
		if [ -f $FILE ]; then
			FOUND=1

			local OWNER=$(stat -c "%U" $FILE)
			local P1=$(stat -c "%A" $FILE | cut -c2-4)
			local P2=$(stat -c "%A" $FILE | cut -c5-10)

			if [ "$OWNER" = "root" ] || echo "$P1" | grep -qE "w" || echo "$P2" | grep -qE "r|w|x"; then
				DETAILS[$CODE]="소유자 및 권한 확인 필요"
			else
				RESULTS[$CODE]="양호"
				DETAILS[$CODE]="소유자 , 권한 알맞음"

			fi

		else
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="점검 대상 파일 없음"
		fi
	done



	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}






# --------------------------------------------------------------------------------
# U_21. /etc/(r)syslog.conf 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_21(){
	local CODE="U_21"
	NAMES[$CODE]="/etc/(r)syslog.conf 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""
	local VULN=0


	#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2

	local FILEPATH=("/etc/syslog.conf" "/etc/rsyslog.conf")
	local FOUND=0

	for FILE in "${FILEPATH[@]}"; do
		if [ -f $FILE ]; then
			FOUND=1

			local OWNER=$(stat -c "%U" $FILE)

			#소유자 / 그룹 / 기타사용자

			local P1=$(stat -c "%A" $FILE | cut -c2-4)
			local P2=$(stat -c "%A" $FILE | cut -c5-7)
			local P3=$(stat -c "%A" $FILE | cut -c8-10)

			if [ "$OWNER" != "root" ] || echo "$P1" | grep -qE "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "r|w|x"; then
				DETAILS[$CODE]+="$FILE 취약,  소유자 : "$OWNER" , 권한 : "$(stat -c "%A" $FILE)""
				VULN=1	
			fi

		fi

	done


	if [ $FOUND -eq 0 ]; then
		DETAILS[$CODE]="파일이 없습니다."
		RESULTS[$CODE]="양호"
	elif [ $VULN -eq 0 ]; then
		DETAILS[$CODE]="점검 양호"
		RESULTS[$CODE]="양호"

	fi



	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}





# --------------------------------------------------------------------------------
# U_22./etc/services 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_22(){
	local CODE="U_22"
	NAMES[$CODE]="/etc/services 파일 소유자 및 권한 설정"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""
	local VULN=0


	#소유자 권한 확인 변수 P1 / 그룹,사용자 권한 확인 변수 P2

	local FILEPATH=("/etc/services" "/etc/services")
	local FOUND=0

	for FILE in "${FILEPATH[@]}"; do
		if [ -f $FILE ]; then
			FOUND=1

			local OWNER=$(stat -c "%U" $FILE)

			#소유자 / 그룹 / 기타사용자

			local P1=$(stat -c "%A" $FILE | cut -c2-4)
			local P2=$(stat -c "%A" $FILE | cut -c5-7)
			local P3=$(stat -c "%A" $FILE | cut -c8-10)

			if [ "$OWNER" != "root" ] || echo "$P1" | grep -qE "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "w|x"; then
				DETAILS[$CODE]+="$FILE 취약,  소유자 : "$OWNER" , 권한 : "$(stat -c "%A" $FILE)""
				VULN=1	
			fi

		fi

	done


	if [ $FOUND -eq 0 ]; then
		DETAILS[$CODE]="파일이 없습니다."
		RESULTS[$CODE]="양호"
	elif [ $VULN -eq 0 ]; then
		DETAILS[$CODE]="점검 양호"
		RESULTS[$CODE]="양호"

	fi



	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}







# 함수 실행


U_23(){
	local CODE="U_23"
	NAMES[$CODE]="SUID, SGID, Sticky bit 설정 파일 점검"
	RESULTS[$CODE]="양호"  # 기본 값을 양호로 설정
	DETAILS[$CODE]=""

	# 1. SUID / SGID 파일 검색
	local SUID_LIST=$(find / -user root -type f \( -perm -04000 -o -perm -02000 \) -xdev 2>/dev/null)

	# 2. 화이트리스트 배열

	local WHITELIST=(
	"/usr/bin/passwd" "/usr/bin/su" "/usr/bin/sudo" "/usr/bin/chsh"
	"/usr/bin/gpasswd" "/usr/bin/newgrp" "/usr/bin/mount" "/usr/bin/umount"
	"/usr/bin/wall" "/usr/bin/write" "/sbin/unix_chkpwd" "/usr/sbin/unix_chkpwd"
	"/usr/sbin/postdrop" "/usr/sbin/postqueue" "/usr/bin/locate"
	"/usr/sbin/grub2-set-bootflag" "/usr/sbin/pam_timestamp_check"
	"/usr/lib/polkit-1/polkit-agent-helper-1"
	"/usr/libexec/dbus-1/dbus-daemon-launch-helper"
	"/usr/libexec/utempter/utempter" "/usr/libexec/openssh/ssh-keysign"
	"/usr/libexec/sssd/krb5_child" "/usr/libexec/sssd/ldap_child"
	"/usr/libexec/sssd/proxy_child" "/usr/libexec/sssd/selinux_child"
	"/usr/libexec/cockpit-session" "/usr/bin/chage" "/usr/bin/pkexec" "/usr/bin/chfn" "/usr/bin/fusermount" "/sbin/fping" "/usr/sbin/fping"
	)
	local VUL_CHECK=0

	
	if [ -n "$SUID_LIST" ]; then
		while read -r FILE; do
			[ -z "$FILE" ] && continue 

			local IS_SAFE=0

			for SAFE_FILE in "${WHITELIST[@]}"; do
				if [ "$FILE" == "$SAFE_FILE" ]; then
					IS_SAFE=1
					break
				fi
			done

			# 화이트리스트에 없는 파일 발견 시
			if [ $IS_SAFE -eq 0 ]; then
				DETAILS[$CODE]+="[미승인파일 발견: $FILE] \n"
				VUL_CHECK=1
			fi
		done <<< "$SUID_LIST"
	fi

	# 최종 판정
	if [ $VUL_CHECK -eq 1 ]; then
		RESULTS[$CODE]="취약"
	else
		DETAILS[$CODE]="불필요한 SUID/SGID 설정 파일이 없거나 모두 허용된 파일입니다."
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_24. 사용자, 시스템 환경변수 파일 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_24(){
	local CODE="U_24"
	NAMES[$CODE]="사용자, 시스템 환경변수 파일 소유자 및 권한 설정 확인"
	RESULTS[$CODE]="양호"  # 1. 처음엔 양호로 시작하는 것이 깔끔합니다.
	DETAILS[$CODE]=""

	# 점검 대상 환경변수들
	local ENV_FILES=(".profile" ".kshrc" ".cshrc" ".bashrc" ".bash_profile" ".login" ".exrc" ".netrc")
	local VULN_CHECK=0

	# 사용자 계정과 홈 디렉터리 추출
	local USER_HOMES=$(awk -F: '$3 == 0 || $3 >= 1000 {print $1":"$6}' /etc/passwd)

	for ENTRY in $USER_HOMES; do
		# 2. $USER_HOMES가 아닌 현재 줄인 $ENTRY에서 추출해야 합니다.
		local USER=$(echo "$ENTRY" | cut -d: -f1)
		local HOMEPATH=$(echo "$ENTRY" | cut -d: -f2)

		if [ -d "$HOMEPATH" ]; then
			for ENVFILE in "${ENV_FILES[@]}"; do
				# 3. 변수명을 ENVFILE로 통일
				local TARGET_PATH="$HOMEPATH/$ENVFILE"

				if [ -f "$TARGET_PATH" ]; then
					# 4. 변수 앞에 $ 기호를 추가해야 합니다.
					local OWNER=$(stat -c "%U" "$TARGET_PATH")
					local PERM=$(stat -c "%A" "$TARGET_PATH")

					local PERM_GROUP=$(echo "$PERM" | cut -c6)
					local PERM_OTHER=$(echo "$PERM" | cut -c9)

					# [판단 기준] 소유자가 root/해당계정이 아니거나 타인에게 쓰기 권한이 있는 경우
					if [[ "$OWNER" != "root" && "$OWNER" != "$USER" ]] || [[ "$PERM_GROUP" == "w" || "$PERM_OTHER" == "w" ]]; then
						VULN_CHECK=1
						RESULTS[$CODE]="취약"
						DETAILS[$CODE]+="[취약: $TARGET_PATH (소유자:$OWNER, 권한:$PERM , 쓰기권한 삭제 바람)]\n"
					fi
				fi
			done
		fi
	done

	if [ $VULN_CHECK -eq 0 ]; then
		DETAILS[$CODE]="모든 사용자 홈 디렉터리 내 환경변수 파일의 설정이 양호합니다."
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_25. world writable 파일 점검
# --------------------------------------------------------------------------------

U_25(){
	local CODE="U_25"
	NAMES[$CODE]="world writable 파일 점검"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	# /proc, /sys, /dev 디렉토리 제외 및 write 권한 확인
	VULN_FILES=$(find / -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -type f -perm -2 -exec ls -l {} + 2>/dev/null)

	if [ -n "$VULN_FILES" ]; then
		DETAILS[$CODE]="발견된 파일 목록 :\n ${VULN_FILES}"

	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="World Writable 파일 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}





# --------------------------------------------------------------------------------
# U_26. dev 디렉토리 점검
# --------------------------------------------------------------------------------

U_26(){
	local CODE="U_26"
	NAMES[$CODE]="dev 디렉토리 점검"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	local DEV_FILES=$(find /dev -name \(-path "/dev/mqueue" -o -path "/dev/shm" \) -prune -o -type f -print 2>/dev/null)

	if [ -n "$DEV_FILES" ]; then
		DETAILS[$CODE]="/dev 디렉토리 위치한 파일들 체크 필요 : $DEV_FILES"
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="/dev 디렉토리에 파일 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}






# --------------------------------------------------------------------------------
# U_27. $HOME/.rhosts, hosts.equiv 사용 금지
# --------------------------------------------------------------------------------

U_27(){
	local CODE="U_27"
	NAMES[$CODE]="\$HOME/.rhosts, hosts.equiv 사용 금지"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""
	local VULN_CHECK=0

	if [ -f "/etc/hosts.equiv" ]; then
		local OWNER=$(stat -c "%U" /etc/hosts.equiv)
		local PERM=$(stat -c "%A" /etc/hosts.equiv)
		local P1=$(echo "$PERM" | cut -c2-4)
		local P2=$(echo "$PERM" | cut -c5-10)


		if [ "$OWNER" != "root" ] || echo "$P1" | grep -qEi "w" || echo "$P2" | grep -qEi "r|w|x" ; then
			VULN_CHECK=1
			DETAILS[$CODE]="/etc/hosts.equiv 파일 소유자 : $OWNER 권한 : $PERM"
		fi
	fi

	local USER_HOMES=$(awk -F: '$3 == 0 || $3 >= 1000 {print $1":"$6}' /etc/passwd)
	for HOMES in $USER_HOMES; do
		local USER=$(echo "$HOMES" | cut -d: -f1)
		local HOME_DIR=$(echo "$HOMES" | cut -d: -f2)
		local TARGET_PATH="$HOME_DIR/.rhosts"

		if [ -d "$HOME_DIR" ] && [ -f "$TARGET_PATH" ]; then
			local OWNER=$(stat -c "%U" "$TARGET_PATH")
			local PERM=$(stat -c "%A" "$TARGET_PATH")
			local P1=$(echo "$PERM" | cut -c2-4)
			local P2=$(echo "$PERM" | cut -c5-10)

			if [[ "$OWNER" != "root" && "$OWNER" != "$USER" ]] || echo "$P1" |  grep -qE "w|x" || echo "$P2" | grep -qE "r|w|x" || grep -q "+" "$TARGET_PATH"; then
				VULN_CHECK=1
				DETAILS[$CODE]+="취약 : $TARGET_PATH ( 소유자 : $OWNER , 권한 : $PERM , 400 이하 권장 )\n"
			fi

		fi
	done

	if [ $VULN_CHECK -eq 0 ]; then
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="취약한 파일 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_28. 접속 IP 및 포트 제한
# --------------------------------------------------------------------------------

U_28(){
	local CODE="U_28"
	NAMES[$CODE]="접속 IP 및 포트 제한"
	RESULTS[$CODE]="체크필요"
	DETAILS[$CODE]="[/etc/hosts.deny , /etc/hosts.allow] 또는 [firewalld] 또는 [iptables] 또는 외부에서 제어중인지 확인 필요"
	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}





# --------------------------------------------------------------------------------
# U_29. /etc/hosts.lpd 파일의 제거 및 권한 적절성 여부 점검
# --------------------------------------------------------------------------------

U_29(){
	local CODE="U_29"
	NAMES[$CODE]="/etc/hosts.lpd 파일의 제거 및 권한 적절성 여부 점검"
	RESULTS[$CODE]="취약"
	DETAILS[$CODE]=""

	local FILE_PATH="/etc/hosts.lpd"

	if [ -f $FILE_PATH ]; then
		local OWNER=$(stat -c "%U" $FILE_PATH)
		local PERM=$(stat -c "%A" $FILE_PATH)
		local P1=$(echo "$PERM" | cut -c2-4)
		local P2=$(echo "$PERM" | cut -c5-10)

		if [ "$OWNER" != "root" ] || echo "$P1" | grep -qE "w|x" || echo "$P2" | grep -qE "r|w|x"; then
			DETAILS[$CODE]=" 소유자 : ($OWNER) , 권한 : ($PERM) , 400 이하 권장"
		else
			RESULTS[$CODE]="양호"
			DETAILS[$CODE]="권한 및 소유자 양호"
		fi
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="파일 없으므로 양호처리"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_30. UMASK 설정 관리
# --------------------------------------------------------------------------------

U_30(){
    local CODE="U_30"
    NAMES[$CODE]="시스템 UMASK 값이 022 이상 설정 여부 점검"
    RESULTS[$CODE]="취약"
    DETAILS[$CODE]=""

    local FILE_PATH="/etc/profile"
    if [ -f "$FILE_PATH" ]; then
        # 주석 제외, 줄 시작에 umask가 있는 것 중 가장 마지막 줄의 값 추출
        local UMASK_VAL=$(grep -i "^[[:space:]]*umask" "$FILE_PATH" | grep -v "#" | awk '{print $2}' | tail -n 1)
        
        if [ -z "$UMASK_VAL" ]; then
            DETAILS[$CODE]="/etc/profile 내에 유효한 UMASK 설정이 없습니다."
        else
            # 숫자 외의 문자 제거 및 뒤에서 두 자리 추출
            local CLEAN_VAL=$(echo "$UMASK_VAL" | tr -d -c '0-9')
            local CHECK_VAL=$(echo "$CLEAN_VAL" | rev | cut -c 1-2 | rev)

            # 비교 (22보다 작으면 취약)
            if [ "$CHECK_VAL" -lt 22 ]; then
                RESULTS[$CODE]="취약"
                DETAILS[$CODE]="UMASK 값이 낮음. 현재 : $UMASK_VAL (022 이상 권장)"
            else
                RESULTS[$CODE]="양호"
                DETAILS[$CODE]="UMASK 값 ($UMASK_VAL) 설정이 적절합니다."
            fi
        fi
    else
        DETAILS[$CODE]="/etc/profile 파일이 없습니다."
    fi
    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_31. 홈디렉토리 소유자 및 권한 설정
# --------------------------------------------------------------------------------

U_31(){
    local CODE="U_31"
    NAMES[$CODE]="홈 디렉토리의 소유자 외 타 사용자가 해당 홈 디렉토리를 수정할 수 없도록 제한 설정 여부 점검"
    RESULTS[$CODE]="취약"
    DETAILS[$CODE]=""
	local TOTAL_VULN_COUNT=0

	while IFS=: read -r u_user u_pass u_uid u_gid u_info u_home u_shell; do
        # UID 1000 이상, nobody 제외
        if [ "$u_uid" -ge 1000 ] && [ "$u_user" != "nobody" ]; then
            if [ -d "$u_home" ]; then
                local OWNER=$(stat -c "%U" "$u_home")
                # stat -c "%A"의 9번째 글자는 타 사용자(Other)의 쓰기(w) 권한임
                local PERM=$(stat -c "%A" "$u_home" | cut -c9)

                if [ "$OWNER" != "$u_user" ] || [ "$PERM" == "w" ]; then
                    TOTAL_VULN_COUNT=$((TOTAL_VULN_COUNT + 1))
                    RESULTS[$CODE]="취약"
                    DETAILS[$CODE]+="취약 디렉토리 사용자 : $u_user (소유자:$OWNER, 권한:$PERM)\n"
                fi
            fi
        fi
    done < /etc/passwd

	if [ $TOTAL_VULN_COUNT -eq 0 ]; then
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="계정 디렉토리 권한 이상 없음"
	fi

	print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_32. 홈 디렉토리로 지정한 디렉토리의 존재 관리
# --------------------------------------------------------------------------------

U_32(){
    local CODE="U_32"
    NAMES[$CODE]="사용자 계정과 홈 디렉토리의 일치 여부 점검"
    RESULTS[$CODE]="취약" 
    DETAILS[$CODE]=""
    local VULN_CHECK=0
    local VULN_LIST=""

    
    while IFS=: read -r u_user u_pass u_uid u_gid u_info u_home u_shell; do
        
        # 홈 디렉토리 경로가 비어있는 경우
        # 일반 사용자(UID 1000 이상 , 60000 미만)의 홈 디렉토리가 / 인 경우
        if [ "$u_uid" -ge "1000" ] && [ "$u_uid" -lt "60000" ]; then
			if [ "$u_home" == "/" ]; then
				VULN_LIST+=""$u_user" 홈 디렉토리가 "/" 입니다.\n"
				VULN_CHECK=1
				continue;
			elif [ ! -d "$u_home" ]; then
				VULN_LIST+=""$u_user" 홈 디렉토리가 없습니다.\n"
				VULN_CHECK=1
				continue;
			fi

		fi

    done < /etc/passwd

    # 결과 판정
    if [ "$VULN_CHECK" -eq 1 ]; then
        DETAILS[$CODE]="홈 디렉터리 설정 미흡 계정: $VULN_LIST \n"
    else
		RESULTS[$CODE]="양호"
        DETAILS[$CODE]="모든 계정의 홈 디렉터리가 정상적으로 존재합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_33. 숨겨진 파일 및 디렉토리 검색 및 제거
# --------------------------------------------------------------------------------

U_33(){
    local CODE="U_33"
    NAMES[$CODE]="숨겨진 파일 및 디렉터리 검색 및 제거"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local CHECK_LIST=""
    local FOUND_COUNT=0

    # 화이트리스트: 정상적인 숨김 파일들 (정확히 일치하도록 설정)
    local EXCLUDE_LIST="\.bash_logout|\.bash_profile|\.bashrc|\.bash_history|\.config|\.ssh|\.lesshst|\.mysql_history|\.viminfo|\.cache|\.java|\.profile|\.local|\.ansible|\.dbus|\.pki|\.Xauthority|\.gnupg|\.ICEauthority|\.fontconfig|\.X11-unix|\.ICE-unix|\.Test-unix"

    # 전역 위험 디렉터리 리스트 (공용 디렉터리 중심)
    local RISK_DIRS=("/tmp" "/var/tmp" "/dev/shm" "/var/spool/cron" "/var/spool/at")

    # 시스템 위험 디렉터리 점검
    for dir in "${RISK_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # 해당 경로에서 . 과 .. 을 제외한 숨김 항목 검색
            local found=$(find "$dir" -maxdepth 1 -name ".*" ! -name "." ! -name ".." 2>/dev/null | sed "s|$dir/||" | egrep -v "$EXCLUDE_LIST")
            
            if [ -n "$found" ]; then
                for f in $found; do
                    CHECK_LIST+="$f($dir) "
                    ((FOUND_COUNT++))
                done
            fi
        fi
    done

    # 일반 사용자 홈 디렉터리 점검 (UID 1000 이상)
    while IFS=: read -r u_user u_pass u_uid u_gid u_info u_home u_shell; do
        if [ "$u_uid" -ge 1000 ] && [ "$u_user" != "nobody" ] && [ -d "$u_home" ]; then
            local h_files=$(find "$u_home" -maxdepth 1 -name ".*" ! -name "." ! -name ".." 2>/dev/null | sed "s|$u_home/||" | egrep -v "$EXCLUDE_LIST")
            
            if [ -n "$h_files" ]; then
                for hf in $h_files; do
                    CHECK_LIST+="$u_user:$hf "
                    ((FOUND_COUNT++))
                done
            fi
        fi
    done < /etc/passwd

    # [3] 결과 판정
    if [ $FOUND_COUNT -gt 0 ]; then
        RESULTS[$CODE]="체크필요"
        DETAILS[$CODE]="시스템에서 의심스러운 숨김 파일이 발견되었습니다: $CHECK_LIST"
    else
        RESULTS[$CODE]="양호"
        DETAILS[$CODE]="주요 경로 내 의심스러운 숨김 파일이 발견되지 않았습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_34. Finger 서비스 비활성화
# --------------------------------------------------------------------------------

U_34(){
    local CODE="U_34"
    NAMES[$CODE]="Finger 서비스 비활성화 여부 점검"
    RESULTS[$CODE]="취약"
    DETAILS[$CODE]=""
	local VULN_CHECK=0

	# inetd 파일 확인
	if [ -f /etc/inetd.conf ]; then
		if grep -v "^#" /etc/inetd.conf | grep -iq "finger"; then
			VULN_CHECK=1
			DETAILS[$CODE]+="/etc/inetd.conf 파일에 finger 서비스가 활성화"
		fi
	fi

	if [ -d "/etc/xinetd.d" ]; then
		if [ -f "/etc/xinetd.d/finger" ]; then
			if grep -i "disable" /etc/xinetd.d/finger | grep -qi "no"; then
				VULN_CHECK=1
				DETAILS[$CODE]+="/etc/xinetd.d/finger 의 disable 옵션 no "
			fi
		fi
	fi

	if [ "$VULN_CHECK" -eq 1 ]; then
		DETAILS[$CODE]+="Finger 서비스 활성화, 파일 확인 필요."
	else
		RESULTS[$CODE]="양호"
		DETAILS[$CODE]="Finger 서비스 비활성화, 양호"
	fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_35. 공유 서비스에 대한 익명 접근 제한 설정
# --------------------------------------------------------------------------------

U_35(){
	local CODE="U_35"
	NAMES[$CODE]="Anonymous FTP 접속 제한 점검"
    RESULTS[$CODE]="취약"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # ftp, anonymous 계정의 로그인 쉘 확인
    if [ -f "/etc/passwd" ]; then
        while IFS=: read -r u_user u_pass u_uid u_gid u_info u_home u_shell; do
            if [[ "$u_user" == "ftp" || "$u_user" == "anonymous" ]]; then
                # 쉘이 제한되지 않은 경우(nologin, false 가 아님) 취약
                if [[ "$u_shell" != "/sbin/nologin" && "$u_shell" != "/bin/false" ]]; then
                    VULN_FOUND=1
                    DETAILS[$CODE]+="계정($u_user)의 쉘 제한 미흡($u_shell). \n"
                fi
            fi
        done < /etc/passwd
    fi

    # vsFTP anonymous_enable 설정 확인
    local VSFTP_CONF_PATHS=("/etc/vsftpd.conf" "/etc/vsftpd/vsftpd.conf")
    for conf in "${VSFTP_CONF_PATHS[@]}"; do
        if [ -f "$conf" ]; then
            # 주석이 아니면서 YES로 설정된 경우만 추출
            if grep -v "^[[:space:]]*#" "$conf" | grep -i "^anonymous_enable" | grep -qi "YES"; then
                VULN_FOUND=1
                DETAILS[$CODE]+="vsftpd 익명 접속 활성. \n"
            fi
        fi
    done

    #[ProFTPD] <Anonymous ~ftp> 설정 확인
    local PROFTP_CONF_PATHS=("/etc/proftpd.conf" "/etc/proftpd/proftpd.conf")
    for conf in "${PROFTP_CONF_PATHS[@]}"; do
        if [ -f "$conf" ]; then
            if grep -v "^[[:space:]]*#" "$conf" | grep -qi "<Anonymous"; then
                VULN_FOUND=1
                DETAILS[$CODE]+="ProFTPD 익명 접속 활성. \n"
            fi
        fi
    done

	#  /etc/samba/smb.conf 파일 확인
    if [ -f "/etc/samba/smb.conf" ]; then
        # 주석 제외, guest ok 옵션이 yes로 설정되어 있는지 확인
        if grep -v "^[[:space:]]*#" /etc/samba/smb.conf | grep -i "guest ok" | grep -qi "yes"; then
            VULN_FOUND=1
            DETAILS[$CODE]+="/etc/samba/smb.conf 내 guest ok 옵션이 'yes'로 설정되어 있습니다.\n"
        fi
    fi

	if [ -f "/etc/exports" ]; then
        # 주석처리 되지 않은 라인 중 anonuid나 anongid 설정이 있는지 확인
        if grep -v "^[[:space:]]*#" /etc/exports | grep -Eiq "anonuid|anongid"; then
            VULN_FOUND=1
            DETAILS[$CODE]+="/etc/exports 파일 내 익명 접근 설정(anonuid/anongid)이 발견되었습니다.\n"
        fi
    fi

    #최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        # 상세 내용 앞에 요약 문구 추가
        DETAILS[$CODE]="취약 사유: ${DETAILS[$CODE]}"
    else
        RESULTS[$CODE]="양호"
        DETAILS[$CODE]="익명 FTP 접속이 적절히 제한되어 있습니다(계정 쉘 제한 포함).\n"
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_36. 불필요한 r 계열 서비스 비활성화 점검
# --------------------------------------------------------------------------------
U_36(){
	local CODE="U_36"
 	NAMES[$CODE]="불필요한 r 계열 서비스 비활성화 점검"
    RESULTS[$CODE]="취약"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    
    if [ -f "/etc/inetd.conf" ]; then
        if grep -v "^#" /etc/inetd.conf | grep -Eiq "rlogin|rsh|rexec"; then
            VULN_FOUND=1
            DETAILS[$CODE]+="/etc/inetd.conf 내 활성화된 r 계열 서비스 존재. \n"
        fi
    fi

    # xinetd 키워드 포함 파일 전체 검색 및 점검
    if [ -d "/etc/xinetd.d" ]; then
        for svc in "rsh" "rlogin" "rexec"; do
            # compgen을 사용하여 해당 키워드가 포함된 파일이 하나라도 있는지 안전하게 확인
            if compgen -G "/etc/xinetd.d/*$svc*" > /dev/null; then
                for file in /etc/xinetd.d/*"$svc"*; do
                    if [ -f "$file" ]; then
                        # disable 옵션이 no(활성)로 설정되어 있는지 확인
                        if grep -i "disable" "$file" | grep -qi "no"; then
                            VULN_FOUND=1
                            DETAILS[$CODE]+="$(basename "$file") 서비스 활성 상태. \n"
                        fi
                    fi
                done
            fi
        done
    fi


    local systemd_active=$(systemctl list-units --type=service | grep -E "rlogin|rsh|rexec")
    if [ -n "$systemd_active" ]; then
        VULN_FOUND=1
        DETAILS[$CODE]+="현재 실행 중인 r 계열 서비스 유닛 발견. \n"
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        DETAILS[$CODE]="취약 사유: ${DETAILS[$CODE]} \n"
    else
		RESULTS[$CODE]="양호"
        DETAILS[$CODE]="모든 r 계열 서비스가 적절히 비활성화되어 있습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_37. crontab 설정파일 권한 설정 미흡 점검
# --------------------------------------------------------------------------------
U_37() {
    local CODE="U_37"
    NAMES[$CODE]="crontab 설정파일 권한 설정 미흡"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 실행 파일 권한 확인
    local EXEC_FILES=(
        "/usr/bin/crontab" 
        "/usr/bin/at" 
        "/usr/bin/batch"
    )
    for FILE in "${EXEC_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            local OWNER=$(stat -c "%U" "$FILE")
            # Others(P3)에게 권한(r, w, x)이 하나라도 있는지 확인
            local P3=$(stat -c "%A" "$FILE" | cut -c8-10)

            if [ "$OWNER" != "root" ] || [[ "$P3" =~ [rwx] ]]; then
                DETAILS[$CODE]+="[실행파일] $FILE (소유자: $OWNER, 권한: $(stat -c "%A" "$FILE"))\n"
                VULN_FOUND=1
            fi
        fi
    done

    # 2. 설정 파일 및 디렉터리 권한 확인
    local CONF_PATHS=(
        "/var/spool/cron"
        "/etc/cron.allow"
        "/etc/cron.deny"
        "/etc/at.allow"
        "/etc/at.deny"
        "/etc/crontab"
        "/etc/cron.d"
        "/etc/cron.daily"
        "/etc/cron.hourly"
        "/etc/cron.monthly"
        "/etc/cron.weekly"
    )

    for PATH_NAME in "${CONF_PATHS[@]}"; do
        if [ -e "$PATH_NAME" ]; then
            # find를 사용하여 디렉터리 내부 파일까지 모두 점검
            find "$PATH_NAME" -maxdepth 1 2>/dev/null | while read -r TARGET; do
                local OWNER=$(stat -c "%U" "$TARGET")
                local PERM_STR=$(stat -c "%A" "$TARGET")
                local P1=$(echo "$PERM_STR" | cut -c2-4) # Owner
                local P2=$(echo "$PERM_STR" | cut -c5-7) # Group
                local P3=$(echo "$PERM_STR" | cut -c8-10) # Others
                
                # 설정 파일 기준: root 소유, 640(-rw-r-----) 이하 권장
                # P1에 x가 있거나, P2에 w/x가 있거나, P3에 r/w/x가 있으면 취약
                if [ "$OWNER" != "root" ] || echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "r|w|x"; then

                    echo "[설정파일] $TARGET (소유자: $OWNER, 권한: $(stat -c "%a" "$TARGET"))" >> /tmp/u37_tmp
                fi
            done
        fi
    done

    # 임시 파일에서 결과 읽어오기
    if [ -f /tmp/u37_tmp ]; then
        DETAILS[$CODE]+=$(cat /tmp/u37_tmp)
        rm -f /tmp/u37_tmp
        VULN_FOUND=1
    fi

    # 3. 최종 판별
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="\n=> 조치: crontab 관련 파일의 소유자를 root로 변경하고 권한을 640 이하로 설정하십시오."
    else
        DETAILS[$CODE]="crontab 설정 파일의 소유자 및 권한 설정이 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}





# --------------------------------------------------------------------------------
# U_38. 불필요한 서비스(echo, discard, daytime, chargen 등) 비활성화 확인
# --------------------------------------------------------------------------------
U_38() {
    local CODE="U_38"
    NAMES[$CODE]="불필요한 서비스(echo, discard, 등) 활성화 확인"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0
    
    # 점검 대상 서비스 목록
    local TARGET_SERVICES=("echo" "discard" "daytime" "chargen")
    local SERV_REG=$(echo "${TARGET_SERVICES[@]}" | sed 's/ /|/g')

    # 1. inetd 점검
    if [ -f /etc/inetd.conf ]; then
        local INETD_CHECK=$(grep -v "^#" /etc/inetd.conf | grep -E "$SERV_REG")
        if [ -n "$INETD_CHECK" ]; then
            DETAILS[$CODE]+="[inetd] 취약: 다음 서비스가 활성화됨\n$INETD_CHECK\n"
            VULN_FOUND=1
        fi
    fi

    # 2. xinetd 점검
    if [ -d /etc/xinetd.d ]; then
        for SERV in "${TARGET_SERVICES[@]}"; do
            if [ -f "/etc/xinetd.d/$SERV" ]; then
                # disable = no 로 되어 있는지 확인
                local XINETD_CHECK=$(grep -i "disable" "/etc/xinetd.d/$SERV" | grep -i "no")
                if [ -n "$XINETD_CHECK" ]; then
                    DETAILS[$CODE]+="[xinetd] 취약: $SERV 서비스가 활성화됨 (disable = no)\n"
                    VULN_FOUND=1
                fi
            fi
        done
    fi

    # 3. systemd 점검 (Rocky 7, 8, 9 핵심)
    # 서비스와 소켓 형태 모두 점검
    local SYSTEMD_CHECK=$(systemctl list-unit-files | grep -E "$SERV_REG" | grep -E "enabled|static" | grep -v "disabled")
    if [ -n "$SYSTEMD_CHECK" ]; then
        # 실제로 구동 중인지(active) 한 번 더 확인하여 정확도 향상
        local RUNNING_CHECK=$(systemctl list-units --type=service --type=socket | grep -E "$SERV_REG" | grep "active")
        if [ -n "$RUNNING_CHECK" ]; then
            DETAILS[$CODE]+="[systemd] 취약: 불필요한 유닛이 활성화/실행 중임\n$RUNNING_CHECK\n"
            VULN_FOUND=1
        fi
    fi

    # 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
    else
        DETAILS[$CODE]="모든 불필요한 서비스(echo, discard, daytime, chargen)가 비활성화되어 있습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_39. 불필요한 NFS 서비스 비활성화
# --------------------------------------------------------------------------------
U_39() {
    local CODE="U_39"
    NAMES[$CODE]="불필요한 NFS 서비스 비활성화"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 점검 대상 NFS 관련 서비스 목록
    # nfs-server: NFS 서버 데몬
    # rpcbind: NFS 예약 및 연결 관리
    # nfs-mountd: NFS 마운트 요청 처리
    local NFS_SERVICES=("nfs" "nfs-server" "rpcbind" "nfs-mountd" "nfs-idmapd")

    # 1. NFS 서비스 활성화 여부 확인
    for SERV in "${NFS_SERVICES[@]}"; do
        # 서비스가 존재하고, 활성(active) 상태이거나 활성화(enabled) 설정인지 확인
        if systemctl is-active --quiet "$SERV" 2>/dev/null || systemctl is-enabled --quiet "$SERV" 2>/dev/null; then
            DETAILS[$CODE]+="[취약] $SERV 서비스가 활성화 또는 실행 중입니다.\n"
            VULN_FOUND=1
        fi
    done

    # 2. 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="불필요한 NFS 서비스 관련 데몬이 활성화되어 있습니다. 서비스 중지 및 비활성화가 필요합니다."
    else
        DETAILS[$CODE]="불필요한 NFS 서비스 관련 데몬이 모두 비활성화되어 있습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_40. NFS 접근 통제 설정 적용 여부 점검
# --------------------------------------------------------------------------------
U_40() {
    local CODE="U_40"
    NAMES[$CODE]="NFS 접근 통제"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. /etc/exports 파일 존재 여부 확인
    if [ -f /etc/exports ]; then
        # 2. 파일 소유자 및 권한 확인 (Step 1)
        local OWNER=$(stat -c "%U" /etc/exports)
        local PERM=$(stat -c "%A" /etc/exports)
		local P1=$(echo "$PERM" | cut -c2-4)
		local P2=$(echo "$PERM" | cut -c5-7)
		local P3=$(echo "$PERM" | cut -c8-10)

        # 소유자가 root가 아니거나 권한이 644를 초과하는 경우 (Step 3, 4 기반)
        # 판단 기준: 권한이 644 이하인 경우 양호
        if [ "$OWNER" != "root" ]; then
            DETAILS[$CODE]+="[취약] /etc/exports 소유자가 root가 아님 (현재: $OWNER)\n"
            VULN_FOUND=1
        fi

        if echo "$P1" | grep -qE "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE " w|x"; then
            DETAILS[$CODE]+="[취약] /etc/exports 권한이 644를 초과함 (현재: $PERM)\n"
            VULN_FOUND=1
        fi

        # 3. 공유 설정 내용 점검 (Step 2, 5 기반)
        # 모든 호스트(*)에 대해 허용하거나 root_squash 옵션이 없는 경우 점검
        local INSECURE_CONFIG=$(grep -v "^#" /etc/exports | grep -E "\*|no_root_squash")
        if [ -n "$INSECURE_CONFIG" ]; then
            DETAILS[$CODE]+="[취약] 비인가자 접근 가능 또는 root_squash 미설정 발견:\n$INSECURE_CONFIG\n"
            VULN_FOUND=1
        fi
    else
        # 파일이 없는 경우 NFS 서비스를 사용하지 않는 것으로 간주
        DETAILS[$CODE]="NFS 설정 파일(/etc/exports)이 존재하지 않습니다."
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="NFS 접근 통제 설정이 미흡합니다. (판단기준: 소유자 root, 권한 644 이하, 적절한 공유 대상 지정)"
    else
        DETAILS[$CODE]="NFS 접근 통제 설정이 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_41. 불필요한 automountd 제거
# --------------------------------------------------------------------------------
U_41() {
    local CODE="U_41"
    NAMES[$CODE]="불필요한 automountd 제거"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 점검 대상 서비스 목록 (Linux 환경의 autofs 포함)
    local AUTO_SERVICES=("automount" "autofs")

    # 1. automount/autofs 서비스 활성화 여부 확인
    for SERV in "${AUTO_SERVICES[@]}"; do
        # 서비스가 실행 중이거나 부팅 시 자동 실행 설정인지 확인
        if systemctl is-active --quiet "$SERV" 2>/dev/null || systemctl is-enabled --quiet "$SERV" 2>/dev/null; then
            DETAILS[$CODE]+="[취약] $SERV 서비스가 활성화 또는 실행 중입니다.\n"
            VULN_FOUND=1
        fi
    done

    # 2. 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="automountd 서비스가 활성화되어 있습니다. RPC 취약점 및 권한 상승 위험이 존재합니다."
    else
        DETAILS[$CODE]="automountd(autofs) 서비스가 비활성화되어 보안상 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_42. 불필요한 RPC 서비스 제한 (rpc.cmsd, rpc.ttdbserverd 등)
# --------------------------------------------------------------------------------
U_42() {
    local CODE="U_42"
    NAMES[$CODE]="불필요한 RPC 서비스 제한"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 점검 대상 RPC 서비스 키워드
    local RPC_KEYS="rpc|cmsd|ttdbserverd|sadmind|rusersd|walld|sprayd|pcnfsd|rexd"

    # 1. [inetd] /etc/inetd.conf 내 RPC 서비스 확인
    if [ -f /etc/inetd.conf ]; then
        local INETD_RPC=$(grep -v "^#" /etc/inetd.conf | grep -E "$RPC_KEYS")
        if [ -n "$INETD_RPC" ]; then
            DETAILS[$CODE]+="[inetd] 취약: 다음 RPC 서비스 활성\n$INETD_RPC\n"
            VULN_FOUND=1
        fi
    fi

    # 2. [xinetd] /etc/xinetd.d/ 내 RPC 서비스 확인
    if [ -d /etc/xinetd.d ]; then
        # xinetd 디렉토리 내 모든 파일을 열어 RPC 서비스가 disable=no인지 확인
        local XINETD_RPC=$(grep -lE "$RPC_KEYS" /etc/xinetd.d/* 2>/dev/null)
        for FILE in $XINETD_RPC; do
            if grep -i "disable" "$FILE" | grep -iq "no"; then
                DETAILS[$CODE]+="[xinetd] 취약: $(basename "$FILE") 서비스 활성(disable=no)\n"
                VULN_FOUND=1
            fi
        done
    fi

    # 3. [systemd] 불필요한 RPC 서비스 활성화 여부 확인
    # Rocky 7/8/9 핵심 점검: 실행 중이거나(active) 자동 실행(enabled)인지 확인
    local SYSTEMD_RPC=$(systemctl list-units --type=service | grep -iE "$RPC_KEYS" | grep "active")
    if [ -n "$SYSTEMD_RPC" ]; then
        DETAILS[$CODE]+="[systemd] 취약: RPC 서비스 실행 중\n$SYSTEMD_RPC\n"
        VULN_FOUND=1
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 불필요한 RPC 서비스가 활성화되어 있어 버퍼 오버플로우 공격 위험이 있습니다."
    else
        DETAILS[$CODE]="모든 불필요한 RPC 서비스가 적절히 비활성화되어 있습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_43. NIS 서비스 비활성화
# --------------------------------------------------------------------------------
U_43() {
    local CODE="U_43"
    NAMES[$CODE]="NIS 서비스 비활성화"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 이미지(image_4cdd29.png)에 명시된 점검 대상 서비스 목록
    local NIS_SERVICES=("ypserv" "ypbind" "ypxfrd" "rpc.yppasswdd" "rpc.ypupdated")

    # 1. 서비스 활성화 여부 확인 (systemd 기준)
    for SERV in "${NIS_SERVICES[@]}"; do
        # 해당 유닛이 존재하는지 먼저 확인 후 상태 점검
        if systemctl list-unit-files "$SERV.service" &>/dev/null; then
            # 서비스가 실행 중(active)이거나 부팅 시 자동 실행(enabled) 설정인 경우 취약
            if systemctl is-active --quiet "$SERV" 2>/dev/null || systemctl is-enabled --quiet "$SERV" 2>/dev/null; then
                DETAILS[$CODE]+="[취약] NIS 관련 서비스 활성화됨: $SERV\n"
                VULN_FOUND=1
            fi
        fi
    done

    # 2. 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 보안 위협: NIS는 데이터 전송 시 암호화를 지원하지 않아 정보 유출 위험이 있습니다."
    else
        DETAILS[$CODE]="모든 NIS 관련 서비스 데몬이 비활성화되어 보안상 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_44. tftp, talk, ntalk 서비스 비활성화 점검
# --------------------------------------------------------------------------------
U_44_SERVICE_CHECK() {
    local CODE="U_44"
    NAMES[$CODE]="tftp, talk, ntalk 서비스 비활성화"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 점검 대상 서비스 목록 (이미지 기준: tftp, talk, ntalk)
    local TARGET_SERVICES=("tftp" "talk" "ntalk")
    local SERV_REG=$(echo "${TARGET_SERVICES[@]}" | sed 's/ /|/g')

    # 1. [inetd] /etc/inetd.conf 점검
    if [ -f /etc/inetd.conf ]; then
        # 주석(#) 처리되지 않은 활성 서비스 검색
        local INETD_CHECK=$(grep -v "^#" /etc/inetd.conf | grep -E "$SERV_REG")
        if [ -n "$INETD_CHECK" ]; then
            DETAILS[$CODE]+="[inetd] 취약: 다음 서비스가 주석 처리되지 않음\n$INETD_CHECK\n"
            VULN_FOUND=1
        fi
    fi

    # 2. [xinetd] /etc/xinetd.d/ 내 설정 확인
    if [ -d /etc/xinetd.d ]; then
        for SERV in "${TARGET_SERVICES[@]}"; do
            if [ -f "/etc/xinetd.d/$SERV" ]; then
                # disable = no 로 설정되어 활성화된 상태인지 확인
                if grep -i "disable" "/etc/xinetd.d/$SERV" | grep -iq "no"; then
                    DETAILS[$CODE]+="[xinetd] 취약: $SERV 서비스가 활성화됨 (disable = no)\n"
                    VULN_FOUND=1
                fi
            fi
        done
    fi

    # 3. [systemd] 활성화 및 실행 여부 확인 (Rocky 7, 8, 9 핵심)
    # 서비스 유닛 리스트에서 대상 서비스 검색
    local SYSTEMD_CHECK=$(systemctl list-unit-files | grep -E "$SERV_REG" | grep -E "enabled|static")
    if [ -n "$SYSTEMD_CHECK" ]; then
        # 실제로 활성화(enabled)되어 있거나 구동(active) 중인지 정밀 확인
        for SERV in "${TARGET_SERVICES[@]}"; do
            if systemctl is-active --quiet "$SERV" 2>/dev/null || systemctl is-enabled --quiet "$SERV" 2>/dev/null; then
                DETAILS[$CODE]+="[systemd] 취약: $SERV 서비스(또는 소켓)가 활성화/실행 중임\n"
                VULN_FOUND=1
            fi
        done
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 보안 위협: tftp는 인증 절차가 없어 탈취 및 정보 유출에 취약하며, talk는 불필요한 세션을 유발합니다."
    else
        DETAILS[$CODE]="모든 불필요한 서비스(tftp, talk, ntalk)가 비활성화되어 있습니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_45. 메일 서비스 버전 점검 (폐쇄망 전용: 내부 버전 비교 로직)
# --------------------------------------------------------------------------------
U_45() {
    local CODE="U_45"
    NAMES[$CODE]="메일 서비스 버전 점검"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 관리자가 지정한 서비스별 최소 보안 버전 (환경에 맞게 수정 필요)
    # 예: "8.15.2" 형식으로 기입
    local MIN_VER_SENDMAIL="8.15.2"
    local MIN_VER_POSTFIX="3.5.8"
    local MIN_VER_EXIM="4.94.2"

    # 버전 비교 함수 (V1 >= V2 확인)
    # $? -eq 0 이면 양호(최신), 1이면 취약(낮음)
    version_ge() {
        [ "$1" == "$2" ] && return 0
        local IFS=.
        local i ver1=($1) ver2=($2)
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
        for ((i=0; i<${#ver1[@]}; i++)); do
            if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
            if ((10#${ver1[i]} > 10#${ver2[i]})); then return 0; fi
            if ((10#${ver1[i]} < 10#${ver2[i]})); then return 1; fi
        done
        return 0
    }

    local MAIL_SERVICES=("sendmail" "postfix" "exim")

    for SERV in "${MAIL_SERVICES[@]}"; do
        if rpm -q "$SERV" &>/dev/null; then
            # 현재 설치된 버전 추출 (숫자와 점만 추출)
            local CUR_VER=$(rpm -q --qf "%{VERSION}" "$SERV")
            
            # 비교할 기준 버전 설정
            local TARGET_MIN=""
            case "$SERV" in
                sendmail) TARGET_MIN=$MIN_VER_SENDMAIL ;;
                postfix)  TARGET_MIN=$MIN_VER_POSTFIX ;;
                exim)     TARGET_MIN=$MIN_VER_EXIM ;;
            esac

            # 버전 비교 수행
            if ! version_ge "$CUR_VER" "$TARGET_MIN"; then
                # 버전이 낮고, 서비스가 실행 중인 경우 취약
                if systemctl is-active --quiet "$SERV" 2>/dev/null; then
                    DETAILS[$CODE]+="[취약] $SERV 실행 중 (현재: $CUR_VER, 권고: $TARGET_MIN 이상)\n"
                    VULN_FOUND=1
                else
                    # 버전은 낮지만 서비스가 중지된 경우
                    DETAILS[$CODE]+="[정보] $SERV 버전 낮으나 서비스 미실행 (현재: $CUR_VER)\n"
                fi
            else
                DETAILS[$CODE]+="[양호] $SERV 버전 적정 (현재: $CUR_VER)\n"
            fi
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 보안 위협: 보안 패치가 누락된 구버전 메일 서비스는 버퍼 오버플로우 공격에 노출될 수 있습니다.\n"
        DETAILS[$CODE]+="=> 조치: 폐쇄망 내 패치 서버를 통해 $SERV 패키지를 $TARGET_MIN 버전 이상으로 업데이트하십시오."
    elif [[ -z "${DETAILS[$CODE]}" ]]; then
        DETAILS[$CODE]="메일 서비스 패키지가 설치되어 있지 않아 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_45. 메일 서비스 버전 점검 (폐쇄망 전용: 내부 버전 비교 로직)
# --------------------------------------------------------------------------------

U_45() {
    local CODE="U_45"
    NAMES[$CODE]="메일 서비스 버전 점검"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 관리자가 지정한 서비스별 최소 보안 버전 (환경에 맞게 수정 필요)
    # 2026년 01월 기준 최신 버전
    local MIN_VER_SENDMAIL="8.18.2"
    local MIN_VER_POSTFIX="3.9.8"
    local MIN_VER_EXIM="4.99.1"

    # 버전 비교 함수 (V1 >= V2 확인)
    # $? -eq 0 이면 양호(최신), 1이면 취약(낮음)
    version_ge() {
        [ "$1" == "$2" ] && return 0
        local IFS=.
        local i ver1=($1) ver2=($2)
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
        for ((i=0; i<${#ver1[@]}; i++)); do
            if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
            if ((10#${ver1[i]} > 10#${ver2[i]})); then return 0; fi
            if ((10#${ver1[i]} < 10#${ver2[i]})); then return 1; fi
        done
        return 0
    }

    local MAIL_SERVICES=("sendmail" "postfix" "exim")

    for SERV in "${MAIL_SERVICES[@]}"; do
        if rpm -q "$SERV" &>/dev/null; then
            # 현재 설치된 버전 추출 (숫자와 점만 추출)
            local CUR_VER=$(rpm -q --qf "%{VERSION}" "$SERV")
            
            # 비교할 기준 버전 설정
            local TARGET_MIN=""
            case "$SERV" in
                sendmail) TARGET_MIN=$MIN_VER_SENDMAIL ;;
                postfix)  TARGET_MIN=$MIN_VER_POSTFIX ;;
                exim)     TARGET_MIN=$MIN_VER_EXIM ;;
            esac

            # 버전 비교 수행
            if ! version_ge "$CUR_VER" "$TARGET_MIN"; then
                # 버전이 낮고, 서비스가 실행 중인 경우 취약
                if systemctl is-active --quiet "$SERV" 2>/dev/null; then
                    DETAILS[$CODE]+="$SERV 실행 중 (현재: $CUR_VER, 권고: $TARGET_MIN 이상)\n"
                    VULN_FOUND=1
                else
                    # 버전은 낮지만 서비스가 중지된 경우
                    DETAILS[$CODE]+="$SERV 버전 낮으나 서비스 미실행 (현재: $CUR_VER)\n"
					VULN_FOUND=1
                fi
            else
                DETAILS[$CODE]+="[양호] $SERV 버전 적정 (현재: $CUR_VER)\n"
            fi
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="패치 버전이 너무 낮습니다\n"
        DETAILS[$CODE]+="$SERV 패키지를 $TARGET_MIN 버전 이상으로 업데이트하십시오."
    elif [[ -z "${DETAILS[$CODE]}" ]]; then
        DETAILS[$CODE]="메일 서비스 패키지가 설치되어 있지 않아 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}




# --------------------------------------------------------------------------------
# U_46. 일반 사용자의 메일 서비스 실행 방지
# --------------------------------------------------------------------------------
U_46() {
    local CODE="U_46"
    NAMES[$CODE]="일반 사용자의 메일 서비스 실행 방지"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. Sendmail 점검
    if [ -f /etc/mail/sendmail.cf ]; then
        # PrivacyOptions 설정에 restrictqrun 값이 포함되어 있는지 확인
        if ! grep "PrivacyOptions" /etc/mail/sendmail.cf | grep -q "restrictqrun"; then
            DETAILS[$CODE]+="[취약] Sendmail: /etc/mail/sendmail.cf 내 restrictqrun 설정 미비\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] Sendmail: restrictqrun 설정 확인됨\n"
        fi
    fi

    # 2. Postfix 점검
    if [ -f /usr/sbin/postsuper ]; then
        # 일반 사용자(Other)의 실행 권한(x) 유무 확인
        local POSTSUPER_PERM=$(stat -c "%A" /usr/sbin/postsuper | cut -c10)
        if [ "$POSTSUPER_PERM" == "x" ]; then
            DETAILS[$CODE]+="[취약] Postfix: /usr/sbin/postsuper 파일에 일반 사용자 실행 권한 존재\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] Postfix: /usr/sbin/postsuper 일반 사용자 실행 제한됨\n"
        fi
    fi

    # 3. Exim 점검
    if [ -f /usr/sbin/exiqgrep ]; then
        # 일반 사용자(Other)의 실행 권한(x) 유무 확인
        local EXIQGREP_PERM=$(stat -c "%A" /usr/sbin/exiqgrep | cut -c10)
        if [ "$EXIQGREP_PERM" == "x" ]; then
            DETAILS[$CODE]+="[취약] Exim: /usr/sbin/exiqgrep 파일에 일반 사용자 실행 권한 존재\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] Exim: /usr/sbin/exiqgrep 일반 사용자 실행 제한됨\n"
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 각 서비스별 q 옵션 제한 설정 또는 실행 파일 권한 제거(chmod o-x)가 필요합니다."
    else
        # 메일 서비스가 설치되지 않은 경우도 고려
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="메일 서비스(Sendmail, Postfix, Exim)가 설치되어 있지 않아 양호합니다."
        else
            DETAILS[$CODE]+="모든 메일 서비스에 대해 일반 사용자 실행 방지 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_47. 스팸 메일 릴레이 제한 점검
# --------------------------------------------------------------------------------
U_47() {
    local CODE="U_47"
    NAMES[$CODE]="스팸 메일 릴레이 제한"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. Sendmail 점검
    if [ -f /etc/mail/sendmail.cf ]; then
        # 8.9 이상 버전에서 promiscuous_relay 설정이 있는지 확인
        if [ -f /etc/mail/sendmail.mc ]; then
            # 주석(dnl) 처리되지 않은 promiscuous_relay가 있으면 취약
            if grep -v "^dnl" /etc/mail/sendmail.mc | grep -q "promiscuous_relay"; then
                DETAILS[$CODE]+="[취약] Sendmail: /etc/mail/sendmail.mc 내 모든 릴레이 허용(promiscuous_relay) 설정됨\n"
                VULN_FOUND=1
            fi
        fi

        # 8.9 미만 버전 대응 및 access 파일 존재 여부 확인
        if ! grep -q "R$\*" /etc/mail/sendmail.cf 2>/dev/null && [ ! -f /etc/mail/access ]; then
            DETAILS[$CODE]+="[취약] Sendmail: 릴레이 제한 설정(access 파일 등)이 보이지 않음\n"
            VULN_FOUND=1
        fi
    fi

    # 2. Postfix 점검
    if [ -f /etc/postfix/main.cf ]; then
        # smtpd_recipient_restrictions 설정 확인
        local PF_RELAY=$(grep "smtpd_recipient_restrictions" /etc/postfix/main.cf | grep -v "^#")
        if [ -z "$PF_RELAY" ]; then
            DETAILS[$CODE]+="[취약] Postfix: /etc/postfix/main.cf 내 수신 제한(smtpd_recipient_restrictions) 설정 미비\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] Postfix: 릴레이 정책 설정 확인됨\n"
        fi
    fi

    # 3. Exim 점검
    local EXIM_CONF=""
    [ -f /etc/exim/exim.conf ] && EXIM_CONF="/etc/exim/exim.conf"
    [ -f /etc/exim4/exim4.conf ] && EXIM_CONF="/etc/exim4/exim4.conf"

    if [ -n "$EXIM_CONF" ]; then
        # relay_from_hosts 설정 확인
        if ! grep -q "relay_from_hosts" "$EXIM_CONF"; then
            DETAILS[$CODE]+="[취약] Exim: $EXIM_CONF 내 릴레이 허용 네트워크(relay_from_hosts) 설정 미비\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 각 서비스별 릴레이 정책(access 설정, mynetworks 제한 등)을 적용하십시오."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="메일 서비스가 설치되어 있지 않거나 릴레이 정책이 기본적으로 제한되어 양호합니다."
        else
            DETAILS[$CODE]+="모든 활성 메일 서버에 대해 릴레이 제한 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_48. expn, vrfy 명령어 제한 점검
# --------------------------------------------------------------------------------
U_48() {
    local CODE="U_48"
    NAMES[$CODE]="expn, vrfy 명령어 제한"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. Sendmail 점검
    if [ -f /etc/mail/sendmail.cf ]; then
        # PrivacyOptions 설정 확인 (noexpn, novrfy 또는 goaway 포함 여부)
        local PRIV_OPTS=$(grep "^O PrivacyOptions=" /etc/mail/sendmail.cf | cut -d'=' -f2)
        
        # goaway 옵션은 authwarnings, noexpn, novrfy 등을 포함한 단축 옵션임
        if echo "$PRIV_OPTS" | grep -iqE "noexpn|novrfy|goaway"; then
            # 두 옵션이 모두 설정되어 있거나 goaway가 있는지 확인
            if ! echo "$PRIV_OPTS" | grep -iq "goaway" && (! echo "$PRIV_OPTS" | grep -iq "noexpn" || ! echo "$PRIV_OPTS" | grep -iq "novrfy"); then
                DETAILS[$CODE]+="[취약] Sendmail: /etc/mail/sendmail.cf 내 noexpn 또는 novrfy 설정 누락 (현재: $PRIV_OPTS)\n"
                VULN_FOUND=1
            fi
        else
            DETAILS[$CODE]+="[취약] Sendmail: /etc/mail/sendmail.cf 내 명령어 제한 설정(noexpn, novrfy)이 보이지 않음\n"
            VULN_FOUND=1
        fi
    fi

    # 2. Postfix 점검
    if [ -f /etc/postfix/main.cf ]; then
        # disable_vrfy_command 설정이 yes로 되어 있는지 확인
        if ! grep -v "^#" /etc/postfix/main.cf | grep -iq "disable_vrfy_command *= *yes"; then
            DETAILS[$CODE]+="[취약] Postfix: /etc/postfix/main.cf 내 disable_vrfy_command 설정이 yes가 아님\n"
            VULN_FOUND=1
        fi
        # 참고: Postfix는 기본적으로 expn 기능을 허용하지 않음
    fi

    # 3. Exim 점검
    local EXIM_CONF=""
    [ -f /etc/exim/exim.conf ] && EXIM_CONF="/etc/exim/exim.conf"
    [ -f /etc/exim4/exim4.conf ] && EXIM_CONF="/etc/exim4/exim4.conf"

    if [ -n "$EXIM_CONF" ]; then
        # acl_smtp_vrfy 및 acl_smtp_expn 설정이 허용(accept)되어 있는지 확인
        if grep -v "^#" "$EXIM_CONF" | grep -iqE "acl_smtp_vrfy *= *accept|acl_smtp_expn *= *accept"; then
            DETAILS[$CODE]+="[취약] Exim: $EXIM_CONF 내 vrfy 또는 expn 명령어가 허용(accept) 설정됨\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 각 서비스 설정 파일에 noexpn, novrfy, disable_vrfy_command 등을 추가하십시오."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="메일 서비스가 설치되어 있지 않아 양호합니다."
        else
            DETAILS[$CODE]+="모든 메일 서버에 대해 expn, vrfy 명령어 제한 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_49. DNS 보안 버전 패치 점검
# --------------------------------------------------------------------------------
U_49() {
    local CODE="U_49"
    NAMES[$CODE]="DNS 보안 버전 패치"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 2026년 기준 BIND 최신 보안 권고 버전
    local MIN_VER_BIND="9.20.17"

    # 버전 비교 함수 (V1 >= V2 확인)
    version_ge() {
        [ "$1" == "$2" ] && return 0
        local IFS=.
        local i ver1=($1) ver2=($2)
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
        for ((i=0; i<${#ver1[@]}; i++)); do
            if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
            if ((10#${ver1[i]} > 10#${ver2[i]})); then return 0; fi
            if ((10#${ver1[i]} < 10#${ver2[i]})); then return 1; fi
        done
        return 0
    }

    # 2. BIND 설치 및 버전 확인
    if rpm -q bind &>/dev/null; then
        # named -v 실행 결과에서 버전 숫자만 추출
        local CUR_VER=$(named -v 2>/dev/null | awk '{print $2}' | cut -d'-' -f1)
        
        # 3. 서비스 활성화 여부 확인
        if systemctl is-active --quiet named 2>/dev/null; then
            # 버전 비교 수행
            if ! version_ge "$CUR_VER" "$MIN_VER_BIND"; then
                DETAILS[$CODE]+="[취약] BIND 서비스 실행 중 (현재: $CUR_VER, 권고: $MIN_VER_BIND 이상)\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] BIND 버전 적정 (현재 버전 $CUR_VER, 최신 보안 패치 적용됨)\n"
            fi
        else
            # 버전은 낮지만 서비스가 중지된 경우 정보만 기록
            if ! version_ge "$CUR_VER" "$MIN_VER_BIND"; then
                DETAILS[$CODE]+="[정보] BIND 버전 낮으나 서비스 미실행 (현재: $CUR_VER)\n"
            else
                DETAILS[$CODE]+="[양호] BIND 설치됨 (버전 $CUR_VER, 서비스 미실행)\n"
            fi
        fi
    else
        DETAILS[$CODE]="DNS(BIND) 패키지가 설치되어 있지 않아 양호합니다."
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 패키지를 $MIN_VER_BIND 이상으로 업데이트하거나, 사용하지 않는 경우 서비스를 비활성화하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_50. DNS Zone Transfer 설정 점검
# --------------------------------------------------------------------------------
U_50() {
    local CODE="U_50"
    NAMES[$CODE]="DNS ZoneTransfer 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 점검 대상 DNS 설정 파일 경로 (이미지 가이드 기준)
    local CONF_FILES=(
        "/etc/named.conf"
        "/etc/bind/named.conf"
        "/etc/bind/named.conf.options"
        "/etc/named.boot"
    )

    local FILE_EXISTS=0

    for FILE in "${CONF_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            FILE_EXISTS=1
            # 2. allow-transfer 또는 xfinets 설정 확인
            # 주석(#, //) 처리되지 않은 행에서 검색
            local TRANSFER_CHECK=$(grep -vE "^\s*#|^\s*//" "$FILE" | grep -iE "allow-transfer|xfinets")

            if [ -z "$TRANSFER_CHECK" ]; then
                # 설정 자체가 없는 경우 (기본적으로 모든 사용자에게 허용될 수 있음)
                DETAILS[$CODE]+="[취약] $FILE: allow-transfer(또는 xfinets) 설정이 존재하지 않습니다.\n"
                VULN_FOUND=1
            else
                # 'any' 키워드가 포함되어 있어 모든 사용자에게 허용된 경우
                if echo "$TRANSFER_CHECK" | grep -iq "any"; then
                    DETAILS[$CODE]+="[취약] $FILE: Zone 전송이 모든 사용자(any)에게 허용되어 있습니다.\n"
                    VULN_FOUND=1
                else
                    DETAILS[$CODE]+="[양호] $FILE: Zone 전송 제한 설정이 확인되었습니다. ($TRANSFER_CHECK)\n"
                fi
            fi
        fi
    done

    # 3. 결과 판정
    if [ "$FILE_EXISTS" -eq 0 ]; then
        DETAILS[$CODE]="DNS(BIND) 설정 파일이 존재하지 않아 양호합니다."
    elif [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: allow-transfer { <허용할 IP>; }; 설정을 통해 인가된 서버로만 제한하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_51. DNS 서비스의 취약한 동적 업데이트 설정 금지 점검
# --------------------------------------------------------------------------------
U_51() {
    local CODE="U_51"
    NAMES[$CODE]="DNS 취약한 동적 업데이트 설정 금지"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 점검 대상 DNS 설정 파일 경로 
    local CONF_FILES=(
        "/etc/named.conf"
        "/etc/bind/named.conf"
        "/etc/bind/named.conf.options"
    )

    local FILE_EXISTS=0

    for FILE in "${CONF_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            FILE_EXISTS=1
            # 2. allow-update 설정 확인 (주석 제외)
            local UPDATE_CHECK=$(grep -vE "^\s*#|^\s*//" "$FILE" | grep -i "allow-update")

            if [ -n "$UPDATE_CHECK" ]; then
                # allow-update 설정이 존재하는 경우, 적절한 제한이 있는지 확인
                # 'any' 키워드가 포함되어 있거나, 구체적인 제한(none 또는 특정 IP)이 없는 경우 점검
                if echo "$UPDATE_CHECK" | grep -iq "any"; then
                    DETAILS[$CODE]+="[취약] $FILE: 동적 업데이트가 모든 사용자(any)에게 허용되어 있습니다.\n"
                    VULN_FOUND=1
                elif echo "$UPDATE_CHECK" | grep -iqE "none|{[^}]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
                    # none 또는 특정 IP 리스트가 있는 경우 양호로 간주
                    DETAILS[$CODE]+="[양호] $FILE: 적절한 동적 업데이트 제한 설정이 확인되었습니다.\n"
                else
                    # 설정은 있으나 형식이 모호한 경우
                    DETAILS[$CODE]+="[취약] $FILE: 동적 업데이트 설정이 미흡합니다. ($UPDATE_CHECK)\n"
                    VULN_FOUND=1
                fi
            else
                # 기본값이 보안상 안전할 수 있으나, 가이드라인에 따라 명시적 설정을 권장
                DETAILS[$CODE]+="[정보] $FILE: allow-update 설정이 명시되어 있지 않습니다. (기본값 확인 필요)\n"
            fi
        fi
    done

    # 3. 결과 판정
    if [ "$FILE_EXISTS" -eq 0 ]; then
        DETAILS[$CODE]="DNS(BIND) 설정 파일이 존재하지 않아 양호합니다."
    elif [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: allow-update { none; }; 또는 특정 IP로 제한하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_52. Telnet 서비스 비활성화 점검
# --------------------------------------------------------------------------------
U_52() {
    local CODE="U_52"
    NAMES[$CODE]="Telnet 서비스 비활성화"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. [inetd] /etc/inetd.conf 내 Telnet 서비스 확인
    if [ -f /etc/inetd.conf ]; then
        # 주석(#) 처리되지 않은 활성 telnet 서비스 검색
        local INETD_TELNET=$(grep -v "^#" /etc/inetd.conf | grep -i "telnet")
        if [ -n "$INETD_TELNET" ]; then
            DETAILS[$CODE]+="[inetd] 취약: Telnet 서비스가 주석 처리되지 않음\n"
            VULN_FOUND=1
        fi
    fi

    # 2. [xinetd] /etc/xinetd.d/telnet 설정 확인
    if [ -f /etc/xinetd.d/telnet ]; then
        # disable = no 로 설정되어 활성화된 상태인지 확인
        if grep -i "disable" /etc/xinetd.d/telnet | grep -iq "no"; then
            DETAILS[$CODE]+="[xinetd] 취약: Telnet 서비스가 활성화됨 (disable = no)\n"
            VULN_FOUND=1
        fi
    fi

    # 3. [systemd] Telnet 소켓 및 서비스 상태 확인 (Rocky 7, 8, 9 핵심)
    # 서비스 유닛 리스트에서 telnet 관련 유닛 검색
    if systemctl list-unit-files | grep -iq "telnet"; then
        # 실제로 활성화(enabled)되어 있거나 구동(active) 중인지 확인
        if systemctl is-active --quiet telnet.socket 2>/dev/null || systemctl is-enabled --quiet telnet.socket 2>/dev/null; then
            DETAILS[$CODE]+="[systemd] 취약: telnet.socket 유닛이 활성화/실행 중임\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: Telnet 서비스를 중지 및 비활성화하고, SSH(Secure Shell)를 사용하십시오."
    else
        DETAILS[$CODE]="Telnet 서비스가 비활성화되어 보안상 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_53. FTP 서비스 정보 노출 제한 점검 (vsFTP, ProFTP)
# --------------------------------------------------------------------------------
U_53() {
    local CODE="U_53"
    NAMES[$CODE]="FTP 서비스 정보 노출 제한"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. vsFTPd 점검
    local VSFTP_CONFS=("/etc/vsftpd.conf" "/etc/vsftpd/vsftpd.conf")
    for CONF in "${VSFTP_CONFS[@]}"; do
        if [ -f "$CONF" ]; then
            # ftpd_banner 옵션이 설정되어 있는지 확인 (주석 제외)
            if ! grep -v "^#" "$CONF" | grep -q "ftpd_banner"; then
                DETAILS[$CODE]+="[취약] vsFTPd: $CONF 내 ftpd_banner 설정이 없거나 주석 처리됨\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] vsFTPd: $CONF 내 접속 배너 설정 확인됨\n"
            fi
        fi
    done

    # 2. ProFTPd 점검
    local PROFTP_CONFS=("/etc/proftpd.conf" "/etc/proftpd/proftpd.conf")
    for CONF in "${PROFTP_CONFS[@]}"; do
        if [ -f "$CONF" ]; then
            # ServerIdent 옵션 확인 (ServerIdent off 또는 별도 배너 설정 시 양호)
            local IDENT_CHECK=$(grep -v "^#" "$CONF" | grep "ServerIdent")
            if [ -z "$IDENT_CHECK" ] || echo "$IDENT_CHECK" | grep -iq "on"; then
                # 기본값이 on이거나 명시적으로 on인 경우 취약
                DETAILS[$CODE]+="[취약] ProFTPd: $CONF 내 ServerIdent 설정이 없거나 on으로 설정됨\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] ProFTPd: $CONF 내 ServerIdent off 또는 배너 제한 설정 확인됨\n"
            fi
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: vsFTPd(ftpd_banner 추가), ProFTPd(ServerIdent off 설정) 조치가 필요합니다."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="FTP 서비스(vsFTP, ProFTP)가 설치되어 있지 않아 양호합니다."
        else
            DETAILS[$CODE]+="모든 FTP 서버에 대해 정보 노출 제한 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_54. 암호화되지 않은 FTP 서비스 비활성화 점검
# --------------------------------------------------------------------------------
U_54() {
    local CODE="U_54"
    NAMES[$CODE]="암호화되지 않은 FTP 서비스 비활성화"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. [inetd] /etc/inetd.conf 점검
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -iq "ftp"; then
            DETAILS[$CODE]+="[inetd] 취약: FTP 서비스가 주석 처리되지 않음\n"
            VULN_FOUND=1
        fi
    fi

    # 2. [xinetd] /etc/xinetd.d/ 내 FTP 설정 점검
    if [ -d /etc/xinetd.d ]; then
        local XINETD_FTP=$(grep -lE "service ftp|service vsftpd" /etc/xinetd.d/* 2>/dev/null)
        for FILE in $XINETD_FTP; do
            if grep -i "disable" "$FILE" | grep -iq "no"; then
                DETAILS[$CODE]+="[xinetd] 취약: $(basename "$FILE") 서비스 활성(disable=no)\n"
                VULN_FOUND=1
            fi
        done
    fi

    # 3. [systemd] 독립형 FTP 서비스 점검 (vsFTP, ProFTP)
    local STANDALONE_FTP=("vsftpd" "proftpd")
    for SERV in "${STANDALONE_FTP[@]}"; do
        if systemctl is-active --quiet "$SERV" 2>/dev/null; then
            DETAILS[$CODE]+="[systemd] 취약: $SERV 서비스가 실행 중임\n"
            VULN_FOUND=1
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 일반 FTP 서비스를 중지 및 비활성화하고, SFTP나 FTPS를 사용하십시오."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="일반 FTP 서비스가 설치되어 있지 않아 양호합니다."
        else
            DETAILS[$CODE]+="모든 일반 FTP 서비스가 적절히 비활성화되어 있습니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_55. FTP 계정 shell 제한 점검
# --------------------------------------------------------------------------------
U_55() {
    local CODE="U_55"
    NAMES[$CODE]="FTP 계정 shell 제한"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. /etc/passwd 파일에서 ftp 계정 존재 여부 및 설정된 쉘 확인
    if grep -q "^ftp:" /etc/passwd; then
        local FTP_SHELL=$(grep "^ftp:" /etc/passwd | awk -F: '{print $7}')
        
        # 2. 부여된 쉘이 /bin/false 또는 /sbin/nologin 인지 확인
        if [[ "$FTP_SHELL" =~ "nologin" ]] || [[ "$FTP_SHELL" =~ "false" ]]; then
            DETAILS[$CODE]+="[양호] ftp 계정에 로그인 제한 쉘($FTP_SHELL)이 적절히 부여되어 있습니다.\n"
        else
            DETAILS[$CODE]+="[취약] ftp 계정에 취약한 쉘($FTP_SHELL)이 부여되어 있습니다.\n"
            VULN_FOUND=1
        fi
    else
        DETAILS[$CODE]+="[양호] 시스템에 ftp 계정이 존재하지 않습니다.\n"
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: usermod -s /sbin/nologin ftp 명령을 통해 쉘을 제한하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_56. FTP 서비스 접근 제어 설정 점검
# --------------------------------------------------------------------------------

U_56() {
    local CODE="U_56"
    NAMES[$CODE]="FTP 서비스 접근 제어 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 점검 대상 파일 목록 
    local TARGET_FILES=(
        "/etc/ftpusers" 
        "/etc/ftpd/ftpusers" 
        "/etc/vsftpd/user_list" 
        "/etc/vsftpd.user_list"
    )

    for FILE in "${TARGET_FILES[@]}"; do
        if [ -f "$FILE" ]; then

            local OWNER=$(stat -c "%U" "$FILE")
            if [ "$OWNER" != "root" ]; then
                DETAILS[$CODE]+="[취약] $FILE: 소유자($OWNER)가 root가 아님\n"
                VULN_FOUND=1
            fi


            local PERM_STR=$(stat -c "%A" "$FILE")
            local P1=$(echo "$PERM_STR" | cut -c2-4) # Owner (6 = rw-)
            local P2=$(echo "$PERM_STR" | cut -c5-7) # Group (4 = r--)
            local P3=$(echo "$PERM_STR" | cut -c8-10) # Others (0 = ---)

            # 640 기준 위반 여부 확인
            if echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "r|w|x"; then
                DETAILS[$CODE]+="[취약] $FILE: 권한($PERM_STR)이 640보다 큼\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] $FILE: 권한($PERM_STR) 및 소유자($OWNER) 설정 적정\n"
            fi
        fi
    done

    # ProFTPd 특정 설정 점검
    local PROFTP_CONF="/etc/proftpd/proftpd.conf"
    if [ -f "$PROFTP_CONF" ]; then
        if ! grep -qi "<Limit LOGIN>" "$PROFTP_CONF"; then
            DETAILS[$CODE]+="[취약] ProFTPd: <Limit LOGIN> 설정 누락\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 파일 소유자를 root로 변경하고 권한을 640(rw-r-----) 이하로 설정하십시오."
    else
        DETAILS[$CODE]+="=> 양호 : 파일이 없거나 설정이 양호합니다."

    fi


    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_57. Ftpusers 파일 설정 (root 계정 접속 제한)
# --------------------------------------------------------------------------------
U_57() {
    local CODE="U_57"
    NAMES[$CODE]="Ftpusers 파일 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 기본 FTP 및 vsFTPd (userlist_enable=NO 환경) 점검
    local FTP_USERS_FILES=("/etc/ftpusers" "/etc/ftpd/ftpusers" "/etc/vsftpd/ftpusers")
    for FILE in "${FTP_USERS_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            # root 문자열이 주석(#) 없이 존재하는지 확인
            if ! grep -v "^#" "$FILE" | grep -qw "root"; then
                DETAILS[$CODE]+="[취약] $FILE: root 계정 접속 제한 설정(root 문자열)이 없음\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] $FILE: root 계정 접속 제한 설정 확인됨\n"
            fi
        fi
    done

    # 2. vsFTPd 특정 점검 (userlist_enable=YES 환경)
    local VSFTP_CONF="/etc/vsftpd/vsftpd.conf"
    if [ -f "$VSFTP_CONF" ]; then
        if grep -qi "userlist_enable=YES" "$VSFTP_CONF"; then
            local UL_FILE="/etc/vsftpd/user_list"
            [ ! -f "$UL_FILE" ] && UL_FILE="/etc/vsftpd.user_list"
            
            if [ -f "$UL_FILE" ]; then
                # userlist_deny가 YES(기본값)인 경우, user_list에 root가 있어야 차단됨
                if ! grep -v "^#" "$UL_FILE" | grep -qw "root"; then
                    DETAILS[$CODE]+="[취약] vsFTPd: $UL_FILE 내에 root 계정 차단 설정이 없음\n"
                    VULN_FOUND=1
                fi
            fi
        fi
    fi

    # 3. ProFTPd 특정 점검
    local PROFTP_CONF="/etc/proftpd/proftpd.conf"
    if [ -f "$PROFTP_CONF" ]; then
        # RootLogin off 설정 여부 확인
        if ! grep -v "^#" "$PROFTP_CONF" | grep -qi "RootLogin *off"; then
            DETAILS[$CODE]+="[취약] ProFTPd: $PROFTP_CONF 내 RootLogin off 설정이 없음\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] ProFTPd: RootLogin off 설정 확인됨\n"
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 각 FTP 설정 파일 및 ftpusers 파일에서 root 계정 접속을 차단(주석 제거 또는 off 설정)하십시오."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="FTP 서비스가 설치되어 있지 않아 양호합니다."
        else
            DETAILS[$CODE]+="모든 활성 FTP 서버에 대해 root 계정 접속 제한 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}




# --------------------------------------------------------------------------------
# U_58. 불필요한 SNMP 서비스 구동 점검
# --------------------------------------------------------------------------------
U_58() {
    local CODE="U_58"
    NAMES[$CODE]="불필요한 SNMP 서비스 구동 점검"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. SNMP 서비스(snmpd) 활성화 여부 확인
    # systemctl list-units 명령으로 현재 로드된 서비스 중 snmpd 검색
    if systemctl list-units --type=service | grep -qw "snmpd.service"; then
        # 서비스가 실행 중(active)이거나 자동 시작(enabled) 설정된 경우 확인
        if systemctl is-active --quiet snmpd || systemctl is-enabled --quiet snmpd; then
            local STATUS=$(systemctl is-active snmpd)
            DETAILS[$CODE]+="[취약] SNMP 서비스(snmpd)가 활성화되어 있습니다. (현재 상태: $STATUS)\n"
            VULN_FOUND=1
        fi
    fi

    # 2. 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: SNMP 서비스를 사용하지 않는 경우 'systemctl stop snmpd' 및 'systemctl disable snmpd' 명령으로 중지하십시오."
    else
        DETAILS[$CODE]="SNMP 서비스가 설치되어 있지 않거나 비활성화되어 있어 양호합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

# --------------------------------------------------------------------------------
# U_59. 안전한 SNMP 버전 사용 점검
# --------------------------------------------------------------------------------
U_59() {
    local CODE="U_59"
    NAMES[$CODE]="안전한 SNMP 버전 사용"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    local SNMP_CONF="/etc/snmp/snmpd.conf"

    if [ -f "$SNMP_CONF" ]; then
        # 1. 설정 파일 내 v1, v2c 활성화 여부 확인
        # rocommunity, rwcommunity는 주로 v1, v2c에서 사용됨
        if grep -v "^#" "$SNMP_CONF" | grep -qE "rocommunity|rwcommunity"; then
            DETAILS[$CODE]+="[취약] $SNMP_CONF: v1, v2c용 커뮤니티 설정이 존재함 (v3 권장)\n"
            VULN_FOUND=1
        fi

        # 2. v3 사용자 존재 여부 확인
        if ! grep -v "^#" "$SNMP_CONF" | grep -qE "createUser|rouser|rwuser"; then
            DETAILS[$CODE]+="[정보] $SNMP_CONF: SNMP v3 사용자 설정이 확인되지 않음\n"
            # v1, v2c가 활성화되어 있다면 취약으로 간주
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: v1, v2c 설정을 제거하고 SHA 등의 인증을 사용하는 v3 이상을 적용하십시오."
    else
        DETAILS[$CODE]="SNMP 서비스가 미설치되었거나 v3 이상을 사용 중입니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_60. SNMP Community String 복잡성 설정 점검
# --------------------------------------------------------------------------------
U_60() {
    local CODE="U_60"
    NAMES[$CODE]="SNMP Community String 복잡성 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    local SNMP_CONF="/etc/snmp/snmpd.conf"

    if [ -f "$SNMP_CONF" ]; then
        # 1. 설정 파일 권한 자리수 체크 (640 이하, root 소유 권장)
        local PERM_STR=$(stat -c "%A" "$SNMP_CONF")
        local P1=$(echo "$PERM_STR" | cut -c2-4) # Owner
        local P2=$(echo "$PERM_STR" | cut -c5-7) # Group
        local P3=$(echo "$PERM_STR" | cut -c8-10) # Others
        
        if echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "r|w|x"; then
            DETAILS[$CODE]+="[취약] $SNMP_CONF: 파일 권한($PERM_STR)이 보안 기준(640)보다 큼\n"
            VULN_FOUND=1
        fi

        # 2. 기본 커뮤니티 스트링(public, private) 사용 여부 점검
        if grep -v "^#" "$SNMP_CONF" | grep -iqE "public|private"; then
            DETAILS[$CODE]+="[취약] $SNMP_CONF: 기본 Community String(public/private)이 사용 중임\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 영문, 숫자, 특수문자를 포함한 10자리 이상의 복잡한 문자열로 변경하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_61. SNMP Access Control 설정 점검
# --------------------------------------------------------------------------------
U_61() {
    local CODE="U_61"
    NAMES[$CODE]="SNMP Access Control 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    local SNMP_CONF="/etc/snmp/snmpd.conf"

    if [ -f "$SNMP_CONF" ]; then
        # 1. com2sec 설정을 통한 접근 제어 확인
        # default 키워드가 포함되어 모든 대상을 허용하는지 확인
        if grep -v "^#" "$SNMP_CONF" | grep -qi "com2sec" | grep -qi "default"; then
            DETAILS[$CODE]+="[취약] $SNMP_CONF: 모든 소스(default)로부터의 SNMP 접근이 허용되어 있음\n"
            VULN_FOUND=1
        elif ! grep -v "^#" "$SNMP_CONF" | grep -qi "com2sec"; then
            DETAILS[$CODE]+="[정보] $SNMP_CONF: 명시적인 접근 제어(com2sec) 설정이 보이지 않음\n"
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: com2sec 설정을 통해 허용할 특정 네트워크 주소 또는 IP를 명시하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_62. 로그인 시 경고 메시지 설정 점검
# --------------------------------------------------------------------------------
U_62() {
    local CODE="U_62"
    NAMES[$CODE]="로그인 시 경고 메시지 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0
    local NEED_CHECK=0

    # 1. 서버 기본 배너 점검 (/etc/motd, /etc/issue)
    for FILE in "/etc/motd" "/etc/issue" "/etc/issue.net"; do
        if [ -f "$FILE" ]; then
            if [ ! -s "$FILE" ]; then
                DETAILS[$CODE]+="[취약] $FILE 파일이 비어 있습니다.\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[정보] $FILE 설정 확인됨 (내용 점검 필요)\n"
                NEED_CHECK=1
            fi
        else
            DETAILS[$CODE]+="[취약] $FILE 파일이 존재하지 않습니다.\n"
            VULN_FOUND=1
        fi
    done

    # 2. SSH 배너 설정 점검 (/etc/ssh/sshd_config)
    if [ -f /etc/ssh/sshd_config ]; then
        if ! grep -v "^#" /etc/ssh/sshd_config | grep -iq "^Banner"; then
            DETAILS[$CODE]+="[취약] SSH: sshd_config 내 Banner 설정이 누락되었습니다.\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[정보] SSH: Banner 설정 확인됨\n"
            NEED_CHECK=1
        fi
    fi

    # 3. 메일(SMTP) 배너 점검
    # Sendmail
    if [ -f /etc/mail/sendmail.cf ]; then
        if ! grep -v "^#" /etc/mail/sendmail.cf | grep -iq "SmtpGreetingMessage"; then
            DETAILS[$CODE]+="[취약] Sendmail: SmtpGreetingMessage 설정 미비\n"
            VULN_FOUND=1
        fi
    fi
    # Postfix
    if [ -f /etc/postfix/main.cf ]; then
        if ! grep -v "^#" /etc/postfix/main.cf | grep -iq "smtpd_banner"; then
            DETAILS[$CODE]+="[취약] Postfix: smtpd_banner 설정 미비\n"
            VULN_FOUND=1
        fi
    fi

    # 4. FTP 배너 점검
    # vsFTPd
    if [ -f /etc/vsftpd/vsftpd.conf ] || [ -f /etc/vsftpd.conf ]; then
        local VSFTP_CONF=$(ls /etc/vsftpd/vsftpd.conf /etc/vsftpd.conf 2>/dev/null | head -n 1)
        if ! grep -v "^#" "$VSFTP_CONF" | grep -iq "ftpd_banner"; then
            DETAILS[$CODE]+="[취약] vsFTPd: ftpd_banner 설정 미비\n"
            VULN_FOUND=1
        fi
    fi

    # 5. DNS(BIND) 버전 정보 숨김 점검
    if [ -f /etc/named.conf ]; then
        if ! grep -v "^#" /etc/named.conf | grep -iq "version"; then
            DETAILS[$CODE]+="[취약] DNS: named.conf 내 version 정보 숨김 설정 미비\n"
            VULN_FOUND=1
        fi
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
    elif [ "$NEED_CHECK" -eq 1 ]; then
        RESULTS[$CODE]="체크필요"
        DETAILS[$CODE]+="=> 모든 서비스에 배너 설정이 존재하나, 문구 내에 버전 정보가 포함되어 있는지 수동 점검이 필요합니다."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_63. sudo 명령어 접근 관리 점검
# --------------------------------------------------------------------------------
U_63() {
    local CODE="U_63"
    NAMES[$CODE]="sudo 명령어 접근 관리"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    local SUDOERS_FILE="/etc/sudoers"

    # 1. 파일 존재 여부 확인
    if [ -f "$SUDOERS_FILE" ]; then
        # 2. 소유자 점검 (root 여부)
        local OWNER=$(stat -c "%U" "$SUDOERS_FILE")
        if [ "$OWNER" != "root" ]; then
            DETAILS[$CODE]+="[취약] $SUDOERS_FILE: 소유자($OWNER)가 root가 아닙니다.\n"
            VULN_FOUND=1
        fi

        # 3. 권한 점검 (자리수 방식: 640 체크)
        local PERM_STR=$(stat -c "%A" "$SUDOERS_FILE")
        local P1=$(echo "$PERM_STR" | cut -c2-4)
        local P2=$(echo "$PERM_STR" | cut -c5-7)
        local P3=$(echo "$PERM_STR" | cut -c8-10)

        # 640 기준 위반 여부 확인
        # P1에 x가 있거나, P2에 w/x가 있거나, P3에 r/w/x가 있으면 취약
        if echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "r|w|x"; then
            DETAILS[$CODE]+="[취약] $SUDOERS_FILE: 파일 권한($PERM_STR)이 보안 기준(640)보다 큽니다.\n"
            VULN_FOUND=1
        else
            DETAILS[$CODE]+="[양호] $SUDOERS_FILE: 소유자(root) 및 권한($PERM_STR) 설정이 적절합니다.\n"
        fi
    else
        DETAILS[$CODE]="시스템에 /etc/sudoers 파일이 존재하지 않아 양호합니다."
    fi

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: chown root /etc/sudoers 및 chmod 640 /etc/sudoers를 실행하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}


# --------------------------------------------------------------------------------
# U_64. 주기적 보안 패치 및 EOL 버전 점검
# --------------------------------------------------------------------------------
U_64() {
    local CODE="U_64"
    NAMES[$CODE]="주기적 보안 패치 및 EOL 버전 점검"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. OS 정보 및 버전 추출
    local OS_NAME=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local OS_VER=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
    local FULL_VER=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

    # 2. RHEL 계열 EOL(지원 종료) 버전 체크 (2026년 1월 기준)
    case "$OS_NAME" in
        rhel)
            # RHEL 7 이하는 2024년 6월부로 일반 유지보수 종료
            if [ "$OS_VER" -le 7 ]; then
                DETAILS[$CODE]+="[취약] RHEL $OS_VER: 일반 보안 지원이 종료(EOL)된 버전입니다. ($FULL_VER)\n"
                VULN_FOUND=1
            else
                DETAILS[$CODE]+="[양호] RHEL $OS_VER: 현재 보안 지원 범위 내에 있는 버전입니다.\n"
            fi
            ;;
        centos)
            # CentOS 7, 8 및 Stream 8은 모두 지원 종료됨
            # CentOS Stream 9 이상만 유지보수 중
            if [[ "$FULL_VER" =~ "Stream" ]] && [ "$OS_VER" -ge 9 ]; then
                DETAILS[$CODE]+="[양호] CentOS Stream $OS_VER: 보안 지원 범위 내에 있습니다.\n"
            else
                DETAILS[$CODE]+="[취약] CentOS $OS_VER: 모든 CentOS Linux 버전(6, 7, 8)은 지원 종료되었습니다. ($FULL_VER)\n"
                VULN_FOUND=1
            fi
            ;;
        rocky|almalinux)
            # Rocky/Alma Linux 8, 9, 10은 2026년 현재 모두 지원 중
            DETAILS[$CODE]+="[양호] $OS_NAME $OS_VER: 보안 지원 범위 내에 있는 배포판입니다.\n"
            ;;
        *)
            DETAILS[$CODE]+="[정보] 분석되지 않은 배포판입니다. ($FULL_VER) 수동 점검이 필요합니다.\n"
            RESULTS[$CODE]="체크필요"
            ;;
    esac

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 지원 가능한 버전(RHEL 8/9/10, Rocky 8/9/10 등)으로 OS 업그레이드를 수행하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"

}


# --------------------------------------------------------------------------------
# U_65. NTP 및 시각 동기화 설정 점검
# --------------------------------------------------------------------------------
U_65() {
    local CODE="U_65"
    NAMES[$CODE]="NTP 및 시각 동기화 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=1 
    local SERVICE_FOUND=0

    # 1. Chrony 점검
    if systemctl is-active --quiet chronyd 2>/dev/null; then

        SERVICE_FOUND=1

        if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
            DETAILS[$CODE]+="[양호] Chrony 서비스가 실행 중이며 서버와 정상 동기화 중입니다.\n"
            VULN_FOUND=0
        else
            local ERR_LOG=$(chronyc sources 2>/dev/null | grep "^\?" | head -n 1)
            DETAILS[$CODE]+="[취약] Chrony 실행 중이나 동기화 실패 (참조: $ERR_LOG)\n"
        fi
    fi


    if systemctl is-active --quiet ntpd 2>/dev/null; then
        SERVICE_FOUND=1
        if ntpq -pn 2>/dev/null | grep -q "^\*"; then
            DETAILS[$CODE]+="[양호] NTP 서비스가 실행 중이며 서버와 정상 동기화 중입니다.\n"
            VULN_FOUND=0
        else
            DETAILS[$CODE]+="[취약] NTP 실행 중이나 동기화된 서버가 없습니다.\n"
        fi
    fi

    # 서비스가 아예 없는 경우
    if [ "$SERVICE_FOUND" -eq 0 ]; then
        DETAILS[$CODE]+="[취약] 활성화된 시각 동기화 서비스(Chrony, NTP)를 찾을 수 없습니다.\n"
        VULN_FOUND=1
    fi

    # 설정 파일 권한 점검
    local CONF_FILES=("/etc/chrony.conf" "/etc/ntp.conf")
    for CONF in "${CONF_FILES[@]}"; do
        if [ -f "$CONF" ]; then
            local PERM_STR=$(stat -c "%A" "$CONF")
            local P1=$(echo "$PERM_STR" | cut -c2-4)
            local P2=$(echo "$PERM_STR" | cut -c5-7)
            local P3=$(echo "$PERM_STR" | cut -c8-10)

            if echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "w|x"; then
                DETAILS[$CODE]+="[취약] $CONF: 권한($PERM_STR)이 보안 기준(644)을 초과함\n"
                VULN_FOUND=1
            fi
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: 시각 동기화 서비스를 활성화하고 'chronyc sources'에서 '*' 기호가 나타나도록 서버 연동을 완료하십시오."
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}

U_66(){
    
    local CODE="U_66"
    NAMES[$CODE]="정책에 따른 시스템 로깅 설정"
    RESULTS[$CODE]="체크필요"
    DETAILS[$CODE]="/etc/(r)syslog.conf 파일 혹은 /etc/rsyslog.d/default.conf 파일 등에서 로그 기록 정책 확인 필요"

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}



# --------------------------------------------------------------------------------
# U_67. 로그 디렉터리 소유자 및 권한 설정 점검
# --------------------------------------------------------------------------------
U_67() {
    local CODE="U_67"
    NAMES[$CODE]="로그 디렉터리 소유자 및 권한 설정"
    RESULTS[$CODE]="양호"
    DETAILS[$CODE]=""
    local VULN_FOUND=0

    # 1. 점검 대상 주요 로그 파일 목록
    local LOG_FILES=(
        "/var/log/messages"
        "/var/log/secure"
        "/var/log/maillog"
        "/var/log/cron"
        "/var/log/spooler"
        "/var/log/boot.log"
    )

    for FILE in "${LOG_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            # 2. 소유자 점검 (root 여부)
            local OWNER=$(stat -c "%U" "$FILE")
            if [ "$OWNER" != "root" ]; then
                DETAILS[$CODE]+="[취약] $FILE: 소유자($OWNER)가 root가 아닙니다.\n"
                VULN_FOUND=1
            fi

            # 3. 권한 점검
            local PERM_STR=$(stat -c "%A" "$FILE")
            local P1=$(echo "$PERM_STR" | cut -c2-4) 
            local P2=$(echo "$PERM_STR" | cut -c5-7) 
            local P3=$(echo "$PERM_STR" | cut -c8-10) 

            if echo "$P1" | grep -q "x" || echo "$P2" | grep -qE "w|x" || echo "$P3" | grep -qE "w|x"; then
                DETAILS[$CODE]+="[취약] $FILE: 파일 권한($PERM_STR)이 보안 기준(644)보다 큽니다.\n"
                VULN_FOUND=1
            else
                [ "$VULN_FOUND" -eq 0 ] && DETAILS[$CODE]+="[양호] $FILE: 설정 적정\n"
            fi
        fi
    done

    # 최종 결과 판정
    if [ "$VULN_FOUND" -eq 1 ]; then
        RESULTS[$CODE]="취약"
        DETAILS[$CODE]+="=> 조치: chown root <파일> 및 chmod 644 <파일> 명령을 실행하십시오."
    else
        if [ -z "${DETAILS[$CODE]}" ]; then
            DETAILS[$CODE]="점검 대상 로그 파일이 존재하지 않아 양호합니다."
        else
            DETAILS[$CODE]="모든 주요 로그 파일의 소유자(root) 및 권한(644 이하) 설정이 적절합니다."
        fi
    fi

    print_result "$CODE" "${NAMES[$CODE]}" "${RESULTS[$CODE]}" "${DETAILS[$CODE]}"
}






echo "보안점검 시작... "
for task in "${CHECK_LIST[@]}"; do
	if declare -f "$task" > /dev/null; then
		$task
	fi
done




# --------------------------------------------------------------------------------
# 총 합계 출력
# --------------------------------------------------------------------------------

TOTAL=$((GOOD_CNT + VULN_CNT + CHECK_CNT))
SUMMARY="
점검 일자 : $(date)
--------------------------------------------------------
[ 점검 결과 요약 ]
총 항목 수 : $TOTAL
양호      : $GOOD_CNT
취약      : $VULN_CNT
체크필요  : $CHECK_CNT
--------------------------------------------------------

체크 필요항목 : $(echo "${CHECK_UNIT[@]}" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
취약 항목 : $(echo "${VULN_UNIT[@]}" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
"

echo "$SUMMARY"
echo "$SUMMARY" >> "$RESULT_FILE"
echo "점검 완료. 결과 파일: $RESULT_FILE"