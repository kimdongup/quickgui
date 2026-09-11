# M1 Windows ARM64 전용 SPICE backend

2026-09-11 UTC. Windows 실제 SSH 인증·재접속을 먼저 통과한 다음 ARM backend를
준비했다. Homebrew QEMU 11.1.1은 SPICE를 포함하지 않으므로 기존 바이너리를
교체하지 않고 공식 소스로 별도 빌드했다. Intel 바이너리는 사용하지 않았다.

## 소스와 빌드

| 소스 | 공식 URL | SHA256 |
| --- | --- | --- |
| SPICE 0.16.0 | https://www.spice-space.org/download/releases/spice-0.16.0.tar.bz2 | `0a6ec9528f05371261bbb2d46ff35e7b5c45ff89bb975a99af95a5f20ff4717d` |
| QEMU 11.1.1 | https://download.qemu.org/qemu-11.1.1.tar.xz | `079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482` |

다운로드 파일은 인계 문서의 해시와 일치했다. 소스 패치 없이 ARM64에서 빌드했다.
작업 루트는 `/Users/mac/quickemu/validation/windows-arm-spice`이며 소스는 `source`,
빌드는 `spice-build`/`qemu-build`, 전체 로그는 `logs`에 있다. Python venv에는
pyparsing 3.3.2, Meson 1.12.0, Ninja 1.13.2가 설치됐다. 기존 Homebrew 패키지를
업데이트하거나 교체하지 않았다.

SPICE는 다음 옵션으로 구성했다. Homebrew의 JPEG/OpenSSL이 기본 C/C++ 헤더
탐색 경로에 없어서 include/library 경로를 명시했다.

```sh
arm_spice_root=/Users/mac/quickemu/validation/windows-arm-spice
cd "$arm_spice_root/spice-build"
PATH="$arm_spice_root/venv/bin:/opt/homebrew/bin:/usr/bin:/bin" \
PYTHON="$arm_spice_root/venv/bin/python" \
CPPFLAGS='-I/opt/homebrew/opt/jpeg-turbo/include -I/opt/homebrew/opt/openssl@3/include' \
LDFLAGS='-L/opt/homebrew/opt/jpeg-turbo/lib -L/opt/homebrew/opt/openssl@3/lib' \
../source/spice-0.16.0/configure --prefix="$arm_spice_root/prefix" \
  --enable-gstreamer=no --with-sasl=no --enable-smartcard=no \
  --enable-manual=no --disable-static
make -j2
make -j2 check
make install
```

SPICE common 7 + server 18, **25 tests PASS / 0 FAIL**. configure는 non-x86_64
플랫폼의 upstream 시험 범위가 제한적이라는 경고를 냈다. 로컬 제공 테스트 통과를
모든 ARM SPICE 기능의 검증으로 확대하지 않는다.

```sh
cd "$arm_spice_root/qemu-build"
PATH="$arm_spice_root/venv/bin:/opt/homebrew/bin:/usr/bin:/bin" \
PKG_CONFIG_PATH="$arm_spice_root/prefix/lib/pkgconfig" \
../source/qemu-11.1.1/configure --target-list=aarch64-softmmu \
  --prefix="$arm_spice_root/qemu-prefix" --enable-spice --enable-slirp \
  --enable-hvf --enable-cocoa --enable-coreaudio --disable-docs \
  --disable-werror --disable-gtk --disable-sdl --disable-opengl \
  --disable-virglrenderer --disable-guest-agent
"$arm_spice_root/venv/bin/ninja" -j2 qemu-system-aarch64
```

## 배치와 호환성

전용 경로는 `~/Library/Application Support/Quickgui/Backends/windows-arm-spice`다.
`QEMU.app/Contents/MacOS/qemu-system-aarch64`는 Mach-O ARM64다.
`libspice-server.1.dylib`를 같은 앱의 `Contents/Frameworks`로 복사하고 QEMU의
참조를 `@executable_path/../Frameworks/libspice-server.1.dylib`로 바꿨다.
라이브러리와 앱을 ad-hoc 재서명했으며 QEMU에는 upstream의 hypervisor entitlement를
적용했다. `codesign --verify --deep --strict` exit 0이다.

Homebrew `spicy` 0.42_3 ARM64의 사본은 `SPICE Viewer.app`으로 등록했다.
실행 인자는 `--uri=spice+unix://<socket>`이며 공백이 있는 실행 파일 경로를 한 인자로
처리한다. `manifest.json`에는 소스·설치 바이너리 해시와 버전을 기록했다.
이 묶음은 호스트 Homebrew dylib와 `/opt/homebrew/share/qemu`에 의존하며,
다른 Mac으로 옮길 수 있는 독립 배포 패키지가 아니다. 바이너리는 Git에 넣지 않는다.

원래 `/opt/homebrew/bin/qemu-system-aarch64`는 작업 시작 시 검증용으로 복사한
바이너리와 해시가 일치한다. 기존 설치 앱과 기본 Cocoa backend를 교체하지 않았다.

## 네이티브 구현과 실사용 검증 범위

`dedd646`은 선택형 `spiceEnabled` metadata와 현재 세션의 `spiceSocket`을 구분한다.
backend의 ARM64 slice, SPICE 옵션, HVF와 Cocoa 지원을 확인한다. 없으면 Cocoa로
시작하고 경고를 반환한다. 소켓은 매 실행의 새 `/tmp/qg-win-*` 디렉터리에 만들며
디렉터리 권한은 0700이다. 오래된 소켓을 저장하거나 재사용하지 않는다.

QEMU 인자에 SPICE Unix 서버와 Homebrew ROM 검색 경로만 추가했다. 기존
머신·CPU·ramfb·virtio GPU·USB 키보드/태블릿·NVMe·TPM·Secure Boot 파일을 유지했다.
Windows용 그래픽 드라이버나 전체 SPICE guest tools를 설치하지 않았다.

기존 VM은 Windows 시작 메뉴의 시스템 종료로 프로세스와 owner lock 해제가
확인된 뒤 `before-spice` APFS clone을 만들었다. QMP 종료 요청만으로는 이번
실행에서 종료되지 않아 메뉴를 사용했으며, 강제 종료로 바꾸지 않았다.
같은 VM이 `cocoa+spice`로 시작하고 QMP `query-spice`의 `enabled: true`, server
0.16.0과 실제 Unix 소켓을 반환했다. Cocoa 로그인 화면도 직접 확인했다.
이 서버 시작 결과만으로 SPICE 화면·입력·재접속 PASS를 판정하지 않는다.
실제 viewer 결과는 [연결 기록](M1_WINDOWS_CONNECTION_RESULTS.ko.md)과
[JSON](evidence/m1-windows-connections.json)에서 계속 갱신한다.

## 두 화면과 포인터 수정

첫 실행은 `ramfb`와 `virtio-gpu-pci`를 모두 SPICE에 내보내 display channel
0/1이 생겼다. SPICE 0.16.0 `server/reds.cpp`의 태블릿 기반 client mouse 조건은
단일 display channel이다. 게스트 agent 없이 두 화면을 내보내면 server mouse
상태가 유지되어 검증기의 절대 좌표 클릭을 보낼 수 없었다.

QEMU 11.1.1 `ui/spice-display.c`의 `display` 선택 옵션을 사용해
`ramfb,id=windows-display`와 `-spice ...,display=windows-display`를 지정했다.
PCI GPU를 제거하거나 게스트 드라이버를 바꾸지 않았다. 정상 종료 후 새 backend로
시작하여 display channel 0 하나만 생성되는 것을 확인했다. 검증기의
`--click 400 200`은 client mouse 모드에서 입력을 보내고 실제 잠금 화면을
PIN 로그인 화면으로 전환했다. SSH 전달 포트는 유지하고 SPICE/QMP 소켓은 새로
생성됐다. 이후 메모장 입력과 재접속 검증은 연결 기록에 별도로 남긴다.
