# lts-setup-korean-monitor

lts Ubuntu 서버의 모니터 콘솔(tty1)에 **한글이 나오도록** 설정하는 스크립트입니다.

리눅스 기본 콘솔은 한글 글꼴을 표시하지 못해 한글이 깨져 보입니다. 이 스크립트는 기본 콘솔을 한글을 그릴 수 있는 [kmscon](https://github.com/Aetf/kmscon)으로 바꾸고, 글자가 겹치지 않는 글꼴과 모니터 해상도까지 한 번에 설정합니다. 서버를 재설치한 뒤 명령 한 줄로 같은 환경을 다시 만드는 것이 목적입니다.

## 설정 내용

| 항목 | 기본값 | 설정 위치 |
|---|---|---|
| 콘솔 | kmscon (tty1) | `kmsconvt@.service` 활성화 |
| 글꼴 | Noto Sans Mono CJK KR, 크기 20 | `/etc/kmscon/kmscon.conf` |
| 해상도 | 1680x1050 (연결된 모니터 포트 자동 감지) | `/etc/default/grub.d/99-korean-console.cfg` |

## 요구 사항

- Ubuntu 24.04 LTS, GRUB 부트로더
- `sudo` 권한과 인터넷 연결 (패키지 설치)
- APT universe 저장소 (kmscon이 들어 있음, Ubuntu 기본 설치에는 켜져 있음)
- **그래픽 드라이버를 설치하고 재부팅한 상태**
- 모니터 연결
- SSH 등 모니터 외의 접속 수단 (화면이 나오지 않을 때 복구용으로 권장)

> [!IMPORTANT]
> 모니터 포트 이름(`DP-4` 등)과 지원 해상도 목록은 그래픽 드라이버가 제공합니다. 드라이버를 설치하기 전에는 이름과 목록이 달라지므로, 드라이버를 먼저 설치하고 재부팅한 뒤 스크립트를 실행하세요. NVIDIA GPU라면 다음 명령으로 설치할 수 있습니다.
>
> ```bash
> sudo ubuntu-drivers install
> sudo reboot
> ```

## 사용법

```bash
sudo bash setup-korean-console.sh
sudo reboot
```

해상도와 kmscon 모두 **재부팅해야 적용됩니다.** 모니터 콘솔에서 스크립트를 실행하고 있을 수도 있으므로, 스크립트는 로그인 세션이 끊기지 않도록 kmscon을 바로 재시작하지 않습니다.

### 옵션

환경 변수로 기본값을 바꿀 수 있습니다.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `RESOLUTION` | `1680x1050` | 콘솔 해상도. 빈 값(`RESOLUTION=`)이면 해상도 설정을 건너뜁니다 |
| `CONNECTOR` | 자동 감지 | 모니터 포트 이름 (예: `DP-4`, `HDMI-A-1`). 모니터가 여러 대면 반드시 지정해야 합니다 |
| `FONT_NAME` | `Noto Sans Mono CJK KR` | 글꼴 이름 |
| `FONT_SIZE` | `20` | 글꼴 크기 (포인트) |

```bash
# 해상도를 1280x720으로
sudo RESOLUTION=1280x720 bash setup-korean-console.sh

# 포트를 직접 지정
sudo CONNECTOR=DP-4 RESOLUTION=1920x1080 bash setup-korean-console.sh

# 해상도는 건드리지 않고 한글 콘솔과 글꼴만 설정
sudo RESOLUTION= bash setup-korean-console.sh
```

모니터 포트 이름과 지원 해상도는 다음 명령으로 확인할 수 있습니다.

```bash
for c in /sys/class/drm/card*-*; do echo "${c##*/}: $(cat $c/status) | $(awk '!s[$0]++' $c/modes | tr '\n' ' ')"; done
```

출력의 `card1-DP-4`에서 `card1-`을 뺀 `DP-4`가 포트 이름입니다.

## 스크립트가 하는 일

1. **사전 확인:** 해상도 형식과 GRUB 여부를 확인하고, 연결된 모니터 포트를 찾아 해당 해상도를 지원하는지 봅니다. 여기서 실패하면 **아무것도 바꾸지 않고** 종료합니다.
2. **패키지 설치:** `kmscon`, `fonts-noto-cjk`, `fontconfig`를 설치하고 글꼴을 찾을 수 있는지 확인합니다.
3. **kmscon 설정:** `/etc/kmscon/kmscon.conf`를 작성합니다. 내용이 다른 기존 파일은 `*.bak-YYYYmmdd-HHMMSS`로 백업합니다. 작성한 뒤에는 kmscon이 설정 파일을 읽을 수 있는지 **미리 검사**합니다.
4. **kmscon 활성화:** `kmsconvt@.service`를 활성화해 부팅할 때 tty1에서 기본 콘솔 대신 kmscon이 실행되게 합니다.
5. **해상도 설정:**
   - `/etc/default/grub.d/99-korean-console.cfg`에 커널 부팅 옵션 `video=<포트>:<해상도>`를 추가합니다.
   - `/etc/default/grub`에 같은 포트의 `video=` 옵션이 이미 있으면 백업한 뒤 제거해 중복을 막습니다.
   - `update-grub`을 실행하고, `/boot/grub/grub.cfg`에 반영됐는지 확인합니다.
6. **로케일 확인:** 시스템 로케일이 UTF-8이 아니면 경고합니다.

생성되는 kmscon 설정은 다음과 같습니다.

```ini
font-engine=pango
font-name=Noto Sans Mono CJK KR
font-size=20
drm
term=xterm-256color
```

## 확인

재부팅한 뒤 다음 명령으로 확인합니다.

```bash
# kmscon 실행 여부 (active 여야 정상)
systemctl is-active kmsconvt@tty1

# 부팅 옵션과 실제 화면 해상도
cat /proc/cmdline
cat /sys/class/graphics/fb0/virtual_size

# 글꼴 설정
grep font-name /etc/kmscon/kmscon.conf
```

## 되돌리기

```bash
# 기본 콘솔로 복귀
sudo systemctl disable kmsconvt@.service

# 해상도 설정 제거
sudo rm /etc/default/grub.d/99-korean-console.cfg
sudo update-grub

sudo reboot
```

패키지까지 제거하려면 `sudo apt-get purge kmscon`을 실행합니다.

## 문제 해결

### kmscon이 켜지지 않고 기본 콘솔이 나옴

```bash
systemctl status kmsconvt@tty1
sudo journalctl -u kmsconvt@tty1 -b
```

kmscon은 설정 파일에 **모르는 옵션이 하나라도 있으면 설정 전체를 읽지 못하고 종료**합니다. 실패하면 기본 콘솔로 대신 넘어가서 한글이 깨진 채로 보입니다. 예를 들어 Ubuntu 24.04의 kmscon 9.0.0은 `dpms-timeout` 옵션을 지원하지 않아서 다음 오류와 함께 종료합니다.

```
ERROR: conf: unknown config option 'dpms-timeout'
ERROR: cannot load configuration: -14
```

설정 파일을 직접 고쳤다면 `kmscon --help`로 지원하는 옵션인지 확인하세요.

### 영문 글자가 겹침

글자마다 폭이 다른 글꼴을 쓰면 생깁니다. kmscon은 모든 글자를 같은 폭의 칸에 그리기 때문에 `m`, `W`, `@`처럼 넓은 글자가 옆 칸을 침범합니다.

| 글꼴 | 영문 폭 (1000 기준) | 한글 폭 | 결과 |
|---|---|---|---|
| Noto Sans CJK KR | 270~946, 제각각 | 920 | 영문이 겹침 |
| **Noto Sans Mono CJK KR** | **모두 500** | 920 | 한글도 두 칸(1000) 안에 들어가 겹치지 않음 |

> [!NOTE]
> `fc-list :spacing=mono`에는 `Noto Sans Mono CJK KR`이 나오지 않습니다. 폭이 다른 한글·한자가 한 글꼴에 섞여 있어 fontconfig가 폭이 일정한 글꼴로 분류하지 않기 때문입니다. 영문 폭은 실제로 모두 같습니다.

### 화면이 나오지 않음

SSH로 접속해 해상도 설정을 제거하고 재부팅합니다.

```bash
sudo rm /etc/default/grub.d/99-korean-console.cfg
sudo update-grub
sudo reboot
```

Ubuntu 서버는 기본적으로 부팅 메뉴가 숨겨져 있어(`GRUB_TIMEOUT=0`) 부팅 화면에서 옵션을 고치기 어렵습니다. 원격 접속 수단을 꼭 확보해 두세요.

## 한계

- **한글 입력은 안 됨:** kmscon은 한글을 **표시**만 하고 입력기는 제공하지 않습니다.
- **해상도는 지정한 포트에만 적용:** 모니터를 다른 포트로 옮기면 해상도 설정이 적용되지 않으므로 스크립트를 다시 실행해야 합니다.
- **그래픽 드라이버에 의존:** 드라이버 없이 기본 화면 드라이버만 쓰는 상태에서는 고를 수 있는 해상도가 제한돼 스크립트가 중단될 수 있습니다.

## 확인한 환경

다음 환경에서 설정을 하나씩 직접 적용해 동작을 확인한 뒤, 그 과정을 스크립트로 옮겼습니다.

| 항목 | 값 |
|---|---|
| OS | Ubuntu 24.04.4 LTS |
| kmscon | 9.0.0-5build2 |
| fonts-noto-cjk | 1:20230817+repack1-3 |
| 그래픽 드라이버 | nvidia-driver-580-open (580.178.04) |
| 모니터 | DP-4 연결, 기본 해상도 1920x1280 |
