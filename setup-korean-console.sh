#!/usr/bin/env bash
# 모니터 콘솔(tty1)에 한글이 나오도록 설정한다.
#   - kmscon: 한글을 그릴 수 있는 콘솔로 기본 콘솔을 대체
#   - 글꼴:   Noto Sans Mono CJK KR (영문 폭이 일정해 글자가 겹치지 않음)
#   - 해상도: 커널 부팅 옵션 video=<포트>:<해상도>
#
# 사용법: sudo bash setup-korean-console.sh
#         sudo RESOLUTION=1280x720 bash setup-korean-console.sh
# 대상:   Ubuntu 24.04 + GRUB + 그래픽 드라이버 설치 후 재부팅한 상태
set -euo pipefail

FONT_NAME=${FONT_NAME:-Noto Sans Mono CJK KR}
FONT_SIZE=${FONT_SIZE:-20}
RESOLUTION=${RESOLUTION-1680x1050}   # 빈 값(RESOLUTION=)이면 해상도 설정을 건너뜀
CONNECTOR=${CONNECTOR:-}             # 비우면 연결된 모니터 포트를 자동으로 찾음

KMSCON_CONF=/etc/kmscon/kmscon.conf
GRUB_MAIN=/etc/default/grub
GRUB_DROPIN=/etc/default/grub.d/99-korean-console.cfg

die() {
  printf '오류: %s\n' "$@" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "root 권한이 필요합니다: sudo bash $0"
ts=$(date +%Y%m%d-%H%M%S)

# 1. 해상도를 설정할 수 있는지 먼저 확인한다 (아무것도 바꾸기 전에 실패하도록)
if [[ -n $RESOLUTION ]]; then
  [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]] || die "RESOLUTION은 1680x1050 형식이어야 합니다: $RESOLUTION"
  command -v update-grub >/dev/null ||
    die "update-grub이 없습니다. GRUB을 쓰지 않는다면 RESOLUTION= 으로 해상도 설정을 건너뛰세요."

  if [[ -z $CONNECTOR ]]; then
    connected=()
    for status in /sys/class/drm/card*-*/status; do
      [[ -r $status ]] || continue
      if [[ $(<"$status") == connected ]]; then
        name=$(basename "$(dirname "$status")")
        connected+=("${name#card*-}")
      fi
    done
    if (( ${#connected[@]} == 0 )); then
      die "연결된 모니터를 찾지 못했습니다." \
          "그래픽 드라이버를 설치하고 재부팅했는지, 모니터가 연결됐는지 확인하세요." \
          "포트를 직접 지정하려면: sudo CONNECTOR=DP-4 bash $0"
    elif (( ${#connected[@]} > 1 )); then
      die "모니터가 여러 개 연결돼 있습니다: ${connected[*]}" \
          "포트를 지정하세요: sudo CONNECTOR=${connected[0]} bash $0"
    fi
    CONNECTOR=${connected[0]}
  fi

  connector_dirs=(/sys/class/drm/card*-"$CONNECTOR")
  [[ -e ${connector_dirs[0]} ]] || die "모니터 포트 '$CONNECTOR'를 찾을 수 없습니다."
  modes_file=${connector_dirs[0]}/modes
  if ! grep -qx "$RESOLUTION" "$modes_file"; then
    die "$CONNECTOR 모니터가 $RESOLUTION 해상도를 지원하지 않습니다." \
        "지원 해상도: $(awk '!seen[$0]++' "$modes_file" | tr '\n' ' ')"
  fi
fi

echo "=== 설정값"
echo "글꼴:   $FONT_NAME ($FONT_SIZE)"
if [[ -n $RESOLUTION ]]; then
  echo "해상도: $CONNECTOR $RESOLUTION"
else
  echo "해상도: 건너뜀"
fi
echo

# 2. 패키지 설치
export DEBIAN_FRONTEND=noninteractive
apt-get update
if [[ -z $(apt-cache policy kmscon | awk '/Candidate:/ && $2 != "(none)" {print $2}') ]]; then
  die "kmscon 패키지를 찾을 수 없습니다. universe 저장소를 켜고 다시 실행하세요:" \
      "  sudo add-apt-repository universe"
fi
apt-get install -y kmscon fonts-noto-cjk fontconfig

[[ -n $(fc-list "$FONT_NAME" family) ]] || die "글꼴 '$FONT_NAME'을 찾을 수 없습니다."

# 3. kmscon 설정 (내용이 다른 기존 파일은 백업)
mkdir -p /etc/kmscon
new_conf=$(cat <<EOF
# setup-korean-console.sh 로 생성
# 글자 폭이 일정한 한글 글꼴을 Pango로 그린다 (폭이 제각각인 글꼴은 영문이 겹침)
font-engine=pango
font-name=$FONT_NAME
font-size=$FONT_SIZE

# DRM/KMS로 화면을 그린다
drm

term=xterm-256color
EOF
)
if [[ -f $KMSCON_CONF && $(<"$KMSCON_CONF") != "$new_conf" ]]; then
  cp -a "$KMSCON_CONF" "$KMSCON_CONF.bak-$ts"
fi
printf '%s\n' "$new_conf" > "$KMSCON_CONF"

# kmscon은 모르는 옵션이 하나라도 있으면 설정 전체를 읽지 못하고 종료하므로 미리 검사한다.
# 존재하지 않는 seat를 지정해 화면을 차지하지 않고 설정만 읽게 한다.
check=$(timeout 10 kmscon -c /etc/kmscon --seats=seat-nonexistent --no-switchvt 2>&1 || true)
if grep -q 'cannot load configuration' <<<"$check"; then
  echo "$check" >&2
  die "kmscon이 $KMSCON_CONF 를 읽지 못했습니다."
fi

# 4. 부팅 시 tty1에서 kmscon 실행
systemctl enable kmsconvt@.service

# 5. 해상도 (커널 부팅 옵션)
if [[ -n $RESOLUTION ]]; then
  # 기본 설정 파일에 같은 포트의 video= 가 있으면 제거해 추가 파일과 중복되지 않게 한다
  if grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=.*video=$CONNECTOR:" "$GRUB_MAIN"; then
    cp -a "$GRUB_MAIN" "$GRUB_MAIN.bak-$ts"
    sed -i -E "/^GRUB_CMDLINE_LINUX_DEFAULT=/{s/ *video=$CONNECTOR:[^ \"']*//g; s/=([\"']) +/=\1/}" "$GRUB_MAIN"
  fi

  mkdir -p "$(dirname "$GRUB_DROPIN")"
  cat > "$GRUB_DROPIN" <<EOF
# setup-korean-console.sh 로 생성: 모니터 콘솔 해상도
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT video=$CONNECTOR:$RESOLUTION"
EOF

  update-grub
  grep -q "video=$CONNECTOR:$RESOLUTION" /boot/grub/grub.cfg ||
    die "/boot/grub/grub.cfg 에 video=$CONNECTOR:$RESOLUTION 이 반영되지 않았습니다."
fi

# 6. 로케일 확인 (UTF-8이 아니면 한글이 깨짐)
if ! grep -qiE '^LANG=.*utf-?8' /etc/default/locale 2>/dev/null; then
  echo
  echo "주의: 시스템 로케일이 UTF-8이 아닙니다. 한글이 깨지면 다음을 실행하세요:"
  echo "  sudo update-locale LANG=C.UTF-8"
fi

# 모니터 콘솔에서 이 스크립트를 실행 중일 수 있으므로 kmscon을 바로 재시작하지 않는다
# (재시작하면 tty1 로그인 세션이 끊겨 스크립트도 함께 종료될 수 있음)
echo
echo "완료: 재부팅하면 적용됩니다."
echo "  sudo reboot"
