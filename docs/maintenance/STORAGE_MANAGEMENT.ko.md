# VM·설치 파일 삭제

2026-09-09, macOS 개인 브랜치의 기능이다. 기존 Quickemu VM의 삭제 기능과 별도로
Apple Silicon macOS VM, Windows ARM64 VM, 다운로드한 ISO/IPSW를 관리한다.

## VM 삭제

1. Manager에서 해당 ARM VM의 **Delete VM**을 누른다.
2. VM 폴더 경로와 **Size on disk**를 확인한다.
3. 표시된 VM 이름을 정확히 입력하고 **Delete permanently**를 누른다.

VM 폴더의 디스크·설정·식별 정보·NVRAM·TPM·로그가 영구 삭제된다.
폴더 밖의 원본 ISO/IPSW는 별도 항목으로 관리한다. 취소하면 파일을 변경하지 않는다.
중지된 VM과 실패·취소·중단된 설치를 삭제할 수 있다. ARM VM의 실행·설치·중지 작업이
진행 중이면 먼저 완료하거나 중지해야 한다.
기존 Quickemu .conf VM의 디스크만 삭제/전체 VM 삭제 메뉴는 유지한다.

## 설치 파일 삭제

1. Manager 또는 ARM 다운로더에서 **Installation files**를 연다.
2. 작업 폴더의 **Install Media**에 저장한 완료 파일과 Quickgui에서 선택한 파일이 표시된다.
   다른 위치의 파일은 **Add installation file**로 추가한다.
   이 M1의 Windows ISO는 /Users/mac/Downloads/Win11_25H2_Korean_Arm64_v2.iso를 선택한다.
3. **Delete installation file**에서 경로·크기를 확인하고 파일 이름을 입력한 뒤
   **Delete permanently**를 누른다.

Downloads 폴더 전체를 자동 열람하지 않는다. macOS 파일 선택 창에서 필요한 파일을 선택하며,
추가한 경로는 다음 앱 실행에도 유지한다. 내려받는 중인 .part 파일은 목록에 넣지 않는다.
macOS 설치가 완료되면 IPSW를 별도로 삭제할 수 있다. 설치가 아직 끝나지 않은 Windows VM이
참조하는 ISO는 삭제하지 못한다. Windows 설치 완료를 확인하거나 해당 VM을 삭제한 뒤 파일을 삭제한다.

삭제는 휴지통 이동이 아닌 영구 삭제다. 두 확인 창 모두 이름을 정확하게 입력하기 전에는
삭제 버튼이 활성화되지 않는다.

## 보호와 검사 범위

- VM 파일 잠금, 잔여 소유 프로세스, 설치 미디어의 앱 전용 공유 잠금을 확인한다.
  미디어 잠금은 QEMU 자체 이미지 잠금과 충돌하지 않도록 별도 파일에 둔다.
- 현재 및 이전에 Quickgui에서 확인한 작업 폴더의 native VM과 Quickemu의 리터럴 저장 경로를 검사한다.
  연결되지 않은 기존 작업 폴더, 읽을 수 없는 설정, 계산식으로 된 경로는 확인할 수 없으므로 삭제를 거부한다.
- 확인 창을 띄운 뒤 파일의 식별 정보·수정 시각·크기 또는 VM 폴더 내용이 바뀌면 다시 확인해야 한다.
- symbolic link, 공유 hard link, 다른 볼륨, 중첩된 native VM, 잘못된 잠금/메타데이터는 삭제를 거부한다.
- 실제 삭제 전에 같은 폴더 안의 임시 이름으로 옮겨 새 VM 실행을 막고 다시 검사한다.
  파일 삭제는 디렉터리 핸들을 기준으로 수행하며 링크의 대상 경로를 따라가지 않는다.
  실패하면 남아 있는 데이터의 경로를 표시한다.

Quickgui가 확인한 적 없는 작업 폴더와 외부 프로그램의 모든 참조를 발견하는 기능은 아니다.
다른 프로그램이 파일을 임의로 바꾸는 모든 경쟁을 파일시스템 전체에서 원자적으로 막지는 않는다.

구현과 실제 검증 결과는 [M1_VALIDATION.ko.md](M1_VALIDATION.ko.md)를 따른다.
