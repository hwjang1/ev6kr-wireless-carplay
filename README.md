# EV6 KR 무선 카플레이 (USB Wi-Fi)

무선 모듈(Wi-Fi 칩)이 없는 **국내형 기아 EV6**(`CVEV.KOR`, 펌웨어 260902, Gen5W 표준형 내비)에서
**USB 무선랜카드 핫스팟**으로 **무선 애플 카플레이**를 쓰기 위한 패키지 모음입니다.
핫스팟은 두 가지 구성 중 하나로 띄웁니다.
- **기존 구성**: NEMESIS 패키지 `usbwifi.hotspot` + 동기화 패키지 `ev6kr.usbap.sync`
- **독립 구성**: 이 저장소의 HMG-API 모드 `usb-hotspot-kr` 하나(usbwifi.hotspot 불필요, [hotspot/README.md](hotspot/README.md))
HMG-API의 `wireless-carplay-aa` 모드(미국·캐나다 EV6/아이오닉 5용)를 국내형 EV6와 USB 동글 핫스팟에 맞게 옮겼습니다.

> [!WARNING]
> **모든 사용은 본인 책임입니다.** 이 저장소는 현대자동차·기아·현대모비스·Telechips·Apple과 관계없는 비공식 개인 프로젝트이며, 어떤 보증도 하지 않습니다.
> 설치하면 헤드유닛의 시스템 설정을 바꾸고 순정 라이브러리를 메모리에서 패치합니다. 함께 설치하는 HMG-API는 `/system/bin/app_process`를 교체합니다.
> 이로 인해 생기는 **헤드유닛·차량의 고장, 부팅 불가, 순정 기능 오작동, 데이터 손실, 보증·무상수리 거부, 법규 위반 등 모든 결과는 설치한 사람이 책임집니다.** 작성자와 기여자는 책임지지 않습니다.
> 설치 전에 [면책](#면책)과 [의존 프로젝트](#의존-프로젝트와-제약)를 읽어 주세요.

> **상태 (2026-11-09): 기존 구성(`usbwifi.hotspot` + `ev6kr.usbap.sync` 0.1.12 + 카플레이 모드)과 ipTIME AX900UA(RTL8831BU) 동글로 무선 카플레이가 동작합니다.**
> - **차에서 확인:** 시동 뒤 자동 연결, 24분 주행 중 끊김 없음, 화면과 소리, 클러스터·HUD 길안내(T맵), 차 LTE를 공유하지 않는 순정 방식(iPhone은 자기 셀룰러 사용). 모드는 0.1.10까지 확인했습니다([31](docs/ANALYSIS.md)·[35절](docs/ANALYSIS.md)).
> - **아직 차에서 확인하지 않음:** 모드 0.1.11(T맵 길안내 아이콘 보강), 0.1.12(블루투스가 준비되면 바로 카플레이 시작, 연결 최대 약 10초 단축, [37절](docs/ANALYSIS.md)), 0.1.13(무선에서도 계기판·미디어 위젯에 곡 정보, [39절](docs/ANALYSIS.md)), 네이버지도 길안내(앱 설정의 HUD 스위치를 켠 뒤), ★ 키로 카플레이 열기.
> - RTL8812BU 동글 한 개는 송신부 불량으로 링크가 계속 끊겼습니다([29절](docs/ANALYSIS.md)). 독립 구성(`usb-hotspot-kr`)은 보류 중입니다.
>
> 아래 [알려진 제약](#알려진-제약과-미확인-사항)을 먼저 읽어 주세요.

## 다운로드

[릴리스 페이지](https://github.com/hwjang1/ev6kr-wireless-carplay/releases)에서 받습니다. 지금 판은 **v0.1.13 시험판(Pre-release)**입니다.

| 파일 | 용도 |
|---|---|
| [`ev6kr-wireless-carplay-nemesis.zip`](https://github.com/hwjang1/ev6kr-wireless-carplay/releases/download/v0.1.13/ev6kr-wireless-carplay-nemesis.zip) | **설치용.** USB 최상위에 풀고 꽂으면 NEMESIS에 두 패키지가 나옵니다([설치 순서](#설치-순서) 5단계). 같은 파일이 버전이 붙은 이름(`ev6kr-wireless-carplay-0.1.12-mod0.1.13-nemesis.zip`)으로도 있습니다 |
| [`ev6kr-preflight-usb.zip`](https://github.com/hwjang1/ev6kr-wireless-carplay/releases/download/v0.1.13/ev6kr-preflight-usb.zip) | 설치 전 점검 USB(1단계) |
| [`ev6kr-trylog-usb.zip`](https://github.com/hwjang1/ev6kr-wireless-carplay/releases/download/v0.1.13/ev6kr-trylog-usb.zip) | 문제가 생겼을 때 로그 수집 USB(8단계) |
| [`SHA256SUMS.txt`](https://github.com/hwjang1/ev6kr-wireless-carplay/releases/download/v0.1.13/SHA256SUMS.txt) | 받은 파일 확인용: `shasum -a 256 -c SHA256SUMS.txt` |

USB 메모리는 FAT32나 exFAT로 포맷하고, zip은 **안의 내용물**을 USB 최상위에 풉니다. `packages/` 안의 zip은 풀지 마세요.

이 저장소 밖에서 따로 받아 설치할 것: [NEMESIS](https://github.com/xwtk/hmg_nemesis), [HMG-API](https://github.com/Open-HMG/HMG-API) 1.0.2, [usbwifi.hotspot](https://github.com/GRT47/HKG_5W_USB_Wlan), 그리고 USB 무선랜 동글(확인된 것은 ipTIME AX900UA). 조건과 제약은 [의존 프로젝트와 제약](#의존-프로젝트와-제약)을 보세요.

## 동작 원리

무선 카플레이 연결 순서와 각 단계를 맡는 부분:

| 단계 | 내용 | 담당 |
|---|---|---|
| 1 | iPhone ↔ 헤드유닛 블루투스, iAP2(SPP) 세션 | **브리지**(이 모드, DiPO 안에서 실행): 순정에는 블루투스 iAP2 데이터를 iAP2 서버로 넘기는 부분이 없음 |
| 2 | iAP2로 iPhone에 Wi-Fi 정보(SSID·비밀번호) 전달 | 순정 iAP2 서버. 순정 설정 `ConnectivitySSID`/`ConnectivityPSK`를 보냄. `persist.sys.iap2.wifi=t` 필요(이 모드가 설정) |
| 3 | iPhone이 헤드유닛 핫스팟 접속 | **USB 동글 핫스팟**. **`ev6kr.usbap.sync`**가 순정 카플레이 SSID·비밀번호·5GHz 채널로 맞춰 둠 |
| 4 | Wi-Fi로 카플레이 세션 | 순정 카플레이 라이브러리(국내 V039는 Wi-Fi 세션 자체 지원). 인터페이스 이름 판별 1곳만 1바이트 메모리 패치(이름표에 없는 인터페이스 = 동글의 `rtwlanN`을 Wi-Fi로 판정) |

자세한 분석 근거는 [docs/ANALYSIS.md](docs/ANALYSIS.md)에 있습니다.

## 구성

| 경로 | 내용 |
|---|---|
| [apsync/](apsync/) | NEMESIS 패키지 **`ev6kr.usbap.sync`**: USB 핫스팟(`usbwifi.hotspot`의 `config/hotspot.conf`)의 `AP_SSID`·`AP_PASS`·`AP_HW_MODE`·`AP_CHANNEL`을 순정 카플레이 핫스팟 설정(`/data/misc/wifi/softap.conf`)에 맞춤. 30초마다 확인, 바뀌면 USB 핫스팟 재시작. 제거 시 원래 값 복원 |
| [hotspot/](hotspot/) | HMG-API 모드 **`usb-hotspot-kr`**(독립 구성): 우리 드라이버를 올리고, 순정 hostapd·dnsmasq로 순정 카플레이 SSID·비밀번호의 핫스팟을 띄움. 동글 분리·재연결 감시, 진단·튜닝 포함. usbwifi.hotspot이 설치돼 있으면 꺼져 있음 |
| [driver/](driver/) | 동글 드라이버(RTL8812BU/8822BU, morrownr v5.13.1) 빌드와 Gen5W 수정(**GPL-2.0**). 차량의 `/proc/config.gz`로 빌드 |
| [shared/rtwlan.sh](shared/rtwlan.sh) | 두 구성이 함께 쓰는 동글 쪽 코드: 수신 backlog, netsample, 디버그 logcat, 송신 경로·전력 조정 |
| [mod/](mod/) | HMG-API 모드 **`wireless-carplay-kr`**(NEMESIS 패키지 `hmgapi.wireless-carplay-kr`): 블루투스 브리지, 카플레이 기능 플래그·설정값, 클러스터/HUD 길안내, 무선 오디오 포맷, 인터페이스 이름 패치 |
| [maps/kia/ev6/kor/260902/](maps/kia/ev6/kor/260902/) | 국내형 EV6 260902의 HMG-API 훅 맵(이름만, 앱 코드 없음). 모드가 쓰는 36개 지점 전부 매핑됨 |
| [usb/preflight/](usb/preflight/) | 설치 전 점검 USB(읽기 전용): `EV6KR-PREFLIGHT.txt` |
| [usb/driver-reset/](usb/driver-reset/) | usbwifi.hotspot을 원래 드라이버(v5.8.7.1)로 되돌리는 USB(덮어쓰기 파일 제거 + 지금 드라이버 보고), 실행 뒤 재부팅 |
| [usb/wifi-check/](usb/wifi-check/) | 순정 Wi-Fi를 한 번 켜서 내장 Wi-Fi 모듈이 있는지 확인하는 USB(시험용, 결과는 토스트와 `EV6KR-WIFICHECK.txt`, [ANALYSIS 38절](docs/ANALYSIS.md)). 블루투스·USB가 잠시 끊길 수 있어 끝나면 헤드유닛 재시작 |
| [usb/trylog/](usb/trylog/) | 연결 시도 뒤 로그 수집 USB: `EV6KR-TRYLOG/`(HMG-API 로그, 동기화·진단 로그, USB 핫스팟 로그, 엔진 상태). 휴대폰 이름·주소가 들어갈 수 있어 공개하지 마세요 |
| [tools/build.sh](tools/build.sh) | 빌드: `dist/`에 NEMESIS 패키지·서명된 모드 생성(`build/`·`dist/`는 저장소에 올리지 않음, 아래 [빌드](#빌드)) |
| [tests/apsync-test.sh](tests/apsync-test.sh) | `ev6kr.usbap.sync` 차량 밖 시험 |
| [tests/hotspot-test.sh](tests/hotspot-test.sh) | `usb-hotspot-kr` 서비스 차량 밖 시험 |

## 의존 프로젝트와 제약

이 저장소만으로는 동작하지 않습니다. 아래 프로젝트가 필요하며, 각 프로젝트의 라이선스·동작·업데이트가 이 저장소의 배포 조건과 동작을 제약합니다.

| 프로젝트 | 쓰는 곳 | 필요한 때 | 라이선스·제약 |
|---|---|---|---|
| [NEMESIS](https://github.com/xwtk/hmg_nemesis) (xwtk) | 모든 패키지의 설치, 백그라운드 서비스 실행 | 차에 먼저 설치 | AGPL-3.0. 이 저장소는 NEMESIS를 설치하지 않습니다 |
| [HMG-API](https://github.com/Open-HMG/HMG-API) 1.0.2 | 카플레이 모드와 `usb-hotspot-kr`의 엔진(훅, 기능 플래그, 네이티브 패치). 빌드할 때 옆 폴더의 소스(`HMGAPI_DIR`)를 읽음 | 차에 설치, 빌드 | AGPL-3.0. 이 저장소는 HMG-API의 파생물이라 **AGPL-3.0을 따릅니다**(배포하거나 네트워크로 제공하면 소스 공개). 국내형은 HMG-API 공식 지원 차종이 아니며, 설치 시 `app_process`를 교체합니다 |
| HMG-API `wireless-carplay-aa` 2.1.0 (VysseCodes) | [mod/](mod/)의 바탕 코드 | 빌드 | AGPL-3.0. 바꾼 부분은 [NOTICE.md](NOTICE.md) |
| [usbwifi.hotspot](https://github.com/GRT47/HKG_5W_USB_Wlan) (GRT47, HKG_5W_USB_Wlan) | 기존 구성의 동글 드라이버와 핫스팟 | 기존 구성에서 차에 설치 | **라이선스 파일이 없어** 코드를 복사하지 않습니다. `ev6kr.usbap.sync`는 실행 중에 그 설정 파일의 키 몇 개만 바꿉니다. `AUTO_UPDATE=1`이면 LTE로 스스로 업데이트되어 동작이 바뀔 수 있습니다(2026-11-08 하루에 세 번 바뀜) |
| [morrownr/88x2bu-20210702](https://github.com/morrownr/88x2bu-20210702) (Realtek v5.13.1) | 독립 구성의 동글 드라이버([driver/](driver/)) | 빌드 | GPL-2.0. [driver/](driver/)와 빌드된 `.ko`는 GPL-2.0이며, `.ko`를 배포할 때는 소스와 패치를 함께 둡니다 |
| AOSP `arm-eabi-4.7`, Linux 3.18.24(kernel.org) | 드라이버 빌드 툴체인과 커널 소스 | 빌드(Docker) | 첫 빌드 때 내려받음 |
| JDK, Android SDK(`android.jar`, `d8`), python3, zip | 패키지 빌드 | 빌드 | — |
| 순정 펌웨어 `CVEV.KOR.0000.V039.001.260902` | 모드·레시피·훅 맵의 대상 | 차 | 이 펌웨어 전용입니다. 레시피는 순정 바이트의 해시를 확인하므로, 서비스센터 업데이트 등으로 펌웨어가 바뀌면 패치가 적용되지 않습니다. 제조사 파일은 저장소에 없습니다 |
| USB 무선랜 동글(5GHz AP 지원 Realtek) | 핫스팟 | 차 | 기존 구성: usbwifi.hotspot이 지원하는 RTL8812BU/8822BU/8831BU/8851BU. 독립 구성: RTL8812BU/8822BU만. 끊김 없는 세션은 ipTIME AX900UA(RTL8831BU)에서만 확인했습니다 |
| HMG Leafia Plus(`wireless.carplay.aa`) | — | **함께 설치 불가** | HMG-API와 같이 설치되지 않으므로 먼저 제거합니다 |

## 설치 순서

준비: NEMESIS 설치됨, `usbwifi.hotspot` 설치·**AP(핫스팟) 모드**·동글 연결, **5GHz**.
동글은 확인된 **ipTIME AX900UA**(RTL8831BU)를 권장합니다. 처음에 CD-ROM으로 잡히는 이 동글은 ①이 CD를 꺼내 무선랜으로 바꿉니다.

1. **점검**: 릴리스의 `ev6kr-preflight-usb.zip`을 USB 최상위에 풀고(또는 [usb/preflight/](usb/preflight/)의 두 파일을 복사) → 꽂고 "예" → `EV6KR-PREFLIGHT.txt`의 `[STOP]` 항목을 먼저 해결.
2. **Leafia 제거**: NEMESIS Manager → My Packages → *HMG Leafia Plus - Wireless CarPlay/AA*(`wireless.carplay.aa`) → Uninstall → 헤드유닛 재시작.
   HMG-API는 Leafia와 함께 설치되지 않습니다.
3. **HMG-API 설치**: [Open-HMG/HMG-API](https://github.com/Open-HMG/HMG-API) 1.0.2의 NEMESIS용 zip을 USB에 풀어 설치 → 재시작.
   - 점검에서 `app_process`가 "모르는 빌드"로 나오면, 설치 프로그램이 거부합니다. 진행하려면 USB에 빈 파일 `HMGAPI/FORCE`를 두어야 합니다(**본인 책임**: `/system/bin/app_process`를 HMG-API의 래퍼로 바꾸며, HMG-API 제거 시 원래 파일로 복원됨).
4. **훅 맵 만들기**: HMG-API 앱 → Settings → Hook map → *Map this car from its files* → *Check the map on this car* → 재시작.
   (이 저장소의 [maps/](maps/)는 같은 방법으로 Mac에서 만든 것이라 결과 대조용입니다. adb로 `/data/hmgapi/maps/kia/ev6/kor/260902/`에 넣고 `hmgapid engine verify-map`을 실행해도 됩니다.)
5. **두 패키지 설치**: [릴리스](https://github.com/hwjang1/ev6kr-wireless-carplay/releases)의 `ev6kr-wireless-carplay-nemesis.zip`(직접 빌드했다면 `dist/ev6kr-wireless-carplay-0.1.12-mod0.1.13-nemesis.zip`)을 USB 루트에 풀고 꽂으면 NEMESIS 패키지 스토어에 두 패키지가 나옵니다.
   **① EV6 KR CarPlay Hotspot Sync**를 먼저, 이어서 **② Wireless CarPlay (EV6 KR, USB Wi-Fi)**를 설치합니다.
   - ①은 USB 핫스팟의 SSID·비밀번호를 순정 카플레이 값(`Kia_` + 4글자)으로 바꿉니다. NEMESIS Manager에서 Launch를 누르면 즉시 동기화하고 결과를 알림으로 보여줍니다.
   - ②는 HMG-API 엔진으로 설치·적용됩니다. HMG-API에 등록되지 않은 서명 키라 경고가 나오지만 설치는 됩니다.
   - 하나씩 설치하려면 `ev6kr.usbap.sync-0.1.12-nemesis.zip`, `wireless-carplay-kr-0.1.13-nemesis.zip`을 각각 써도 됩니다. 이전 버전이 깔려 있으면 스토어에서 업데이트로 나옵니다.
6. USB를 빼고 **동글을 꽂은 뒤 헤드유닛 재시작**. 기능 플래그와 훅은 재시작 뒤에 적용됩니다.
7. **연결**: iPhone에서 예전 핫스팟(`HKG_USB_Hotspot`)과 **`Kia_…` 네트워크를 "이 네트워크 설정 지우기"** 하고, 설정 → 일반 → CarPlay에서 이 차를 지웁니다(손으로 입력한 설정이 남아 있으면 카플레이가 받은 설정과 엇갈립니다). iCloud 키체인을 쓰는 다른 Apple 기기에도 같은 네트워크가 남아 있으면 지웁니다. 이어서 블루투스로 연결하고 카플레이 안내에 따라 진행합니다. **핫스팟 비밀번호를 직접 입력하지 마세요.**
8. **안 되면**: 동글을 빼고 로그 수집 USB(릴리스의 `ev6kr-trylog-usb.zip`, 또는 [usb/trylog/](usb/trylog/))를 꽂아 실행 → 화면에 "EV6KR 로그 수집 완료" 토스트가 뜰 때까지(약 1분) 기다렸다가 빼고 `EV6KR-TRYLOG/` 폴더를 보내주세요. 일찍 빼면 파일이 비어 있습니다(설정 파일은 먼저 적용됨).
   시험 버전이라 ①이 진단 로그(카플레이·iAP2·블루투스·핫스팟 관련 태그 전부 + 그 밖의 경고·오류, 1MB 단위 순환)를 기본으로 계속 남깁니다. 이 USB 루트에 빈 파일 `EV6KR-DEBUG-OFF`를 두고 실행하면 꺼집니다(`EV6KR-DEBUG-ON`이면 다시 켜짐).

### 되돌리기

설치의 역순입니다: 모드(`hmgapi.wireless-carplay-kr`) 제거 → `ev6kr.usbap.sync` 제거(USB 핫스팟의 원래 SSID·비밀번호 복원) → 필요하면 HMG-API 제거(`app_process` 원본 복원).
모드의 변경(기능 플래그 1줄, 권한 파일 1개, 설정값 3개)은 HMG-API 엔진이 원본 그대로 되돌립니다. 라이브러리 패치는 메모리에서만 적용되므로 `/system`의 파일은 바뀌지 않습니다.

### 로그

- 핫스팟 동기화: `/data/nemesis/ev6kr.usbap.sync.log`, 진단 logcat `/data/nemesis/ev6kr.usbap.sync.logcat.txt*`
- 모드: `adb logcat -v time -s DiPO:V GPM:V Iap2:V HMG-API:V`(브리지 줄은 `HMG-API: bridge: ...`), 또는 HMG-API 앱의 Car Report
- USB 핫스팟: `/data/local/tmp/usbwifi_hotspot/daemon.log`, `hostapd.log`

### 설정

- 동기화 일시 중지: 빈 파일 `/data/nemesis/ev6kr.usbap.sync.disabled` (앱에서 Launch를 누르면 해제되고 즉시 동기화)
- 순정 카플레이 비밀번호에 영문·숫자 외 문자가 있으면 영문·숫자 12자리로 바꿉니다(iAP2와 같은 `WifiManager` API, 원래 값은 백업 후 제거 시 복원). 그대로 두려면 빈 파일 `/data/nemesis/ev6kr.usbap.sync.keeppsk`
- USB 핫스팟이 STA(클라이언트) 모드일 때는 동기화하지 않습니다.
- 차 LTE 공유: 0.1.12부터 끕니다(순정처럼 iPhone은 자기 셀룰러 사용). 다시 켜려면 `/data/nemesis/ev6kr.usbap.sync.tune`에 `lte_share=1`(trylog USB의 `EV6KR-TUNE.txt`로도 설정)
- 모드 설정(HMG-API 앱): 길안내(tbt), 블루투스 브리지(bridge), 무선 오디오(audio), 무선 카플레이 곡 정보(now_playing, 0.1.13, 기본 켬, 재시작 후 적용: 계기판·미디어 위젯·분할 화면의 곡 제목), 블루투스 준비 즉시 카플레이 시작(early_start, 0.1.12, 기본 켬, 재시작 후 적용), USB 메모리·허브가 유선 안드로이드 오토를 시작하지 않게(usb_drives)

## 빌드

```sh
tools/build.sh keygen     # 처음 한 번: 모드 서명 키 ~/hmg-private/keys/ev6kr-mods.key (저장소 밖, 백업 필수)
tools/build.sh            # 기존 구성: dist/ 에 zip 6개 (두 패키지를 담은 USB 설치본 포함)
driver/build.sh <차량 /proc/config.gz> # 독립 구성의 드라이버 (Docker)
tools/build.sh release    # 릴리스용 파일: dist/release/ (점검·로그 USB zip, SHA256SUMS.txt 포함)
tools/build.sh standalone # 독립 구성: usb-hotspot-kr, 카플레이 모드, 둘을 담은 USB 설치본
sh tests/apsync-test.sh   # 동기화 패키지 시험 (MOCK_SH=mksh 로 차량과 같은 셸 사용 가능)
sh tests/hotspot-test.sh  # 독립 핫스팟 서비스 시험
```

필요: JDK(javac/java), Android SDK(`platforms/android-*/android.jar`, build-tools `d8`), python3, zip, 그리고 옆 폴더의 HMG-API 소스(`HMGAPI_DIR`, 기본 `../HMG-API`, 읽기만 함).
**서명 키는 잃어버리면 같은 모드의 업데이트를 만들 수 없습니다**(차에 설치된 모드가 키에 묶임).

## 알려진 제약과 미확인 사항

- **차량 확인 범위**: 한 대(국내형 EV6, 260902)에서만 확인했습니다. 확인 항목은 맨 위 상태를 보세요.
- **동글**: 끊김 없이 동작을 확인한 동글은 ipTIME AX900UA 하나입니다. RTL8812BU 동글 한 개는 송신 체인 불량으로 링크가 무너졌고, 송신 경로·전력·1T2R 같은 소프트웨어 조정으로도 해결되지 않았습니다([29절](docs/ANALYSIS.md)). 다른 RTL8812BU 제품은 시험하지 않았습니다. 5GHz를 지원하지 않는 동글(예: 2.4GHz 전용 AX300급)은 쓸 수 없습니다.
- **길안내**: 내비 앱이 iAP2 길안내 정보를 보내야 클러스터·HUD에 표시됩니다. T맵은 확인했습니다. 네이버지도는 앱의 CarPlay 설정에서 HUD 스위치를 켜야 하며, 켠 뒤의 결과는 아직 확인하지 않았습니다. 다른 앱은 시험하지 않았습니다.
- **usbwifi.hotspot 자동 업데이트**: `AUTO_UPDATE=1`(기본)이면 LTE로 GitHub에서 스스로 업데이트합니다. 업데이트 중 핫스팟이 몇 분간 반복해서 다시 만들어진 적이 있습니다([26절](docs/ANALYSIS.md)).
- **USB 포트**: 이 차는 데이터 USB 포트가 하나라서, 동글을 꽂아 두면 유선 카플레이·USB 메모리는 허브 없이 쓸 수 없습니다.
- **DiPO의 USB 리셋**: DiPO는 카플레이 세션이 약 6초 안에 열리지 않으면 USB 포트 전원을 껐다 켭니다(유선용 복구). 모드가 동글이 꽂혀 있는 동안(Realtek USB 드라이버에 USB 인터페이스가 묶여 있을 때) DiPO 프로세스에서 이 리셋을 막고, 막든 안 막든 HMG-API 로그에 `USB power reset …`을 남깁니다.
- **USB 핫스팟 복구**: `usbwifi.hotspot` 데몬은 USB 버스 리셋이나 빠른 재연결을 알아채지 못해 핫스팟을 다시 띄우지 않습니다(사라진 `rtwlan0`에 주소가 남고 새 `rtwlanN`은 미설정). 동기화 서비스가 이 상태를 약 1분 30초 뒤 감지해 재시작을 요청합니다. 근본적으로는 USB 패키지 쪽 수정이 필요합니다.
- **카플레이 IE**: 순정은 핫스팟 비콘용 카플레이 정보 요소를 설정에 저장하지만 순정 핫스팟 시작 경로에서 쓰이는 곳은 찾지 못했고, USB 핫스팟에도 넣지 않았습니다. 넣지 않아도 iPhone은 iAP2로 받은 SSID·비밀번호로 접속합니다(iAP2는 채널을 보내지 않으므로 iPhone이 SSID로 찾아갑니다).
- **무선 안드로이드 오토**: 켜지 않았습니다(카플레이 무선 플래그만). 안드로이드 오토 길안내 네이티브 패치는 국내형 라이브러리가 달라 적용되지 않습니다.
- **HMG-API 차량 탐색기**: 국내형 BtSettings에서 `btsettings.projection_helper`를 엉뚱한 클래스로 잡아 그 지점들이 빠집니다(Mac의 `map-car.py`는 찾음). 모드의 지점이 하나라도 빠지면 모드 훅 전체가 꺼지므로, 이 지점을 쓰는 미국·캐나다 전용 메뉴 기능을 뺐습니다.
- **HMG-API 코어**: 국내형은 공식 지원 차종이 아닙니다. `app_process` 빌드 확인이 필요하고, 코어의 일부 부가 기능(버튼 설정 등 68개 지점)은 국내형 맵에 없어 꺼집니다.
- **USB 대시보드와의 관계**: 대시보드에서 AP SSID·비밀번호를 바꾸면 30초 안에 순정 카플레이 값으로 되돌아갑니다(카플레이가 그 값을 iPhone에 주기 때문). 대시보드는 설정값을 따옴표 없이 저장하므로, 순정 비밀번호에 특수문자가 있으면 대시보드 화면에는 따옴표가 붙어 보일 수 있습니다(데몬은 정확히 읽음).
- **셸**: 스크립트는 sh·dash·mksh로 시험합니다(차량은 mksh).
- **독립 구성**: 드라이버의 핫언플러그, dnsmasq의 67번 포트, 순정 방화벽을 차에서 확인하지 못했습니다([hotspot/README.md](hotspot/README.md)).

## 면책

- **비공식 프로젝트입니다.** 현대자동차·기아·현대모비스·Telechips·Apple 등 어떤 제조사의 승인이나 지원도 받지 않았습니다. 상표는 각 소유자의 것입니다.
- **보증하지 않습니다.** 소프트웨어는 "있는 그대로" 제공되며, 법이 허용하는 범위에서 어떤 명시적·묵시적 보증도 하지 않습니다(AGPL-3.0 제15·16조).
- **결과는 설치한 사람이 책임집니다.** 다음을 포함한 모든 손해의 책임은 사용자에게 있습니다.
  - 헤드유닛 부팅 불가나 고장. 복구에 서비스센터 입고가 필요할 수 있습니다.
  - 블루투스 통화, 내비게이션, 카메라 화면 등 순정 기능의 오작동
  - 펌웨어 업데이트 뒤 동작 중단이나 충돌, 설정·데이터 손실
  - 제조사·판매점의 보증이나 무상수리 거부
- **이 저장소가 하지 않는 일:** 차량 CAN 메시지를 직접 보내지 않고, MICOM·부트로더·모뎀 펌웨어를 바꾸지 않습니다. 이것이 안전을 보장한다는 뜻은 아닙니다.
- **전파 관련:** USB 무선랜 동글은 국내 전파 인증(KC)을 받은 제품을 쓰세요. 송신 경로·전력 조정 기능은 시험용이며, 인증 범위를 벗어나는 설정은 사용자 책임입니다.
- **운전 중에는 조작하지 마세요.** 설치·설정·로그 수집은 정차 상태에서 하고, 카플레이는 도로교통법에 맞게 사용하세요.
- **개인정보:** [usb/trylog/](usb/trylog/) 수집본에는 휴대폰 이름, 블루투스·Wi-Fi 주소, 헤드유닛 정보가 들어갈 수 있습니다. 공개 이슈에 그대로 올리지 마세요.

## 라이선스

AGPL-3.0 ([LICENSE](LICENSE)). 의존 프로젝트의 라이선스는 [의존 프로젝트와 제약](#의존-프로젝트와-제약)에 있습니다. HMG-API의 코드를 바탕으로 하며, 출처는 [NOTICE.md](NOTICE.md)에 있습니다. [driver/](driver/)와 `usb-hotspot-kr`에 들어가는 드라이버(`.ko`)는 GPL-2.0입니다.
제조사 앱·라이브러리는 포함하지 않습니다(해시 기반 레시피, md5 목록, 훅 이름만).
