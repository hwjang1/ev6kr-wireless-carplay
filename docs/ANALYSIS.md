# 국내형 EV6 무선 카플레이 분석

대상: `ro.build.product=CVEV.KOR.0000.V039.001.260902`, `ro.mobis.onebindir=cvev_kr`, `tcc803x`, Android 4.4.2, `ro.product.opt.stepofspec=110`.
순정 파일은 차량에서 읽기 전용으로 수집해 직접 만든 dex 파서와 `objdump`(Thumb-2)로 분석했습니다. 수집 파일은 저장소에 넣지 않습니다.

## 1. 하드웨어

| 항목 | 결과 |
|---|---|
| 순정 Wi-Fi 칩 | 없음. 보드가 알려 주는 Wi-Fi 모듈 버전이 3이고, 순정 WifiService가 이 값을 "Wi-Fi 하드웨어 없음"으로 처리합니다(38절). `/sys/bus/sdio/devices`도 비어 있음. `/system/wifi`에 `bcmdhd.ko`와 BCM89359 펌웨어 파일만 있음 |
| USB 동글 | `0bda:b812`(RTL88x2BU, 88x2bu 드라이버), 480Mbps. 인터페이스 `rtwlan0`(미사용) / `rtwlan1`(AP, `192.168.43.1/24`) |
| 동글 AP 설정 | `hw_mode=a`, `channel=149`, `ieee80211n=1`(HT20). Mac 기준 신호 -30dBm, ping 손실 0%, 평균 11ms |
| 데이터 USB 포트 | 1개(`4-1`). 동글과 USB 메모리를 동시에 쓰려면 허브 필요 |
| 방화벽 | INPUT/OUTPUT/FORWARD 정책 ACCEPT, 화이트리스트 없음(미국 아이오닉 6과 다름). 동글 데몬이 `rtwlan1` 허용 규칙을 맨 앞에 넣음 |
| Bonjour | `/system/bin/mdnsd` 실행 중, UDP 5353. `rtwlan1`에 IPv6 링크 로컬 주소 있음 |

## 2. 카플레이 네이티브 라이브러리

| 파일 | md5 | 판정 |
|---|---|---|
| `libCarPlayCore.so` | `ef49c09b…` | 국내 V039: Wi-Fi 세션 자체 지원(레시피 `native` 줄) |
| `libCarPlayUtils.so` | `e85385d7…` | AAC/Opus 변환기 내장(레시피 `native` 줄) |
| `libCarPlayAudio.so` | `2b748bf8…` | 미국판과 다른 파일이지만 무선 오디오 포맷 레시피의 검증 영역 5곳이 모두 원본과 일치 → 적용 가능 |
| `libautoreceiver_infobank.so` | `c4fbccdf…` | 안드로이드 오토 길안내 레시피 불일치 → 제외 |
| `libCarPlayCoreUtils.so` | `cf3cc23d…` | 아래 3절의 이름 판별 → 새 레시피 |

## 3. 인터페이스 이름으로 연결 종류 판별

- **`libCarPlayCoreUtils.so` `SocketGetInterfaceInfo`**(Apple CoreUtils): 소켓 인터페이스 이름을 `strcmp`로 비교합니다.
  - `rndis0`, `ncm0` → 8(USB)
  - `wlan0`, `tether` → 2(Wi-Fi)
  - 그 밖(`rtwlan1` 포함) → 1
  - 문자열은 `.rodata` 0x8a2b8부터 8바이트 칸: `rndis0`, `ncm0`, `wlan0`(0x8a2c8), `tether`(0x8a2d0).
  - 동글 인터페이스 이름은 꽂을 때마다 바뀝니다(`rtwlan0`, `rtwlan1`, `rtwlan2`…, 11절).
  - **레시피 `carplay-coreutils-usbwifi`**(0.1.1): 표에 없는 이름의 기본값 `movs r5,#1`(0x4de84)을 `#2`로 바꾸는 1바이트 패치입니다. 이 분기로 오는 경로는 `tether` 비교 실패 하나뿐이고, USB(`ncm0`/`rndis0` → 8)는 그대로입니다.
    0.1.0의 이름 바꾸기(`wlan0`→`rtwlan0`, `tether`→`rtwlan1`)는 `rtwlan2` 이상을 놓쳐서 대체했습니다.
  - HMG-API가 앱 프로세스 메모리에서만 적용하므로 `/system` 파일은 그대로입니다.
- **`libCarPlay.so` `TccCarPlayInternal_GetTccCarPlayTransportTypeFromInterfaceName`**(TCC 포팅 계층): `strstr`로 {`ncm`,`usb`} / {`wlan`,`tether`} 포함 여부를 봅니다. `rtwlan1`은 `wlan`을 포함하므로 이미 Wi-Fi로 판정됩니다.

## 4. iAP2 서버(`com.tcc.iap2server`)

- `Iap2InitInformationMsg.checkSupportsFeatures`:
  - `persist.sys.iap2.wifi`(`t`/`f`) → `iAP2UsedWifiInformation`
  - `persist.iap2.iden.wireless` → `iAP2UsedWirelessTransport`
  - 기능 `com.hkmc.software.connectivity.carplay_wireless`가 있으면 `iAP2UsedBluetoothTransport`, `iAP2UsedWirelessTransport`, `iAP2UsedLegacyBtKeyExchange`를 켬
  - `ro.product.opt.stepofspec >= 999`는 길안내(RouteGuidance)에만 관여
- `Iap2Service.OnSendWifiInformation`:
  - `WifiManager.getWifiApConfiguration()`을 리플렉션으로 호출합니다.
  - 현대 확장 필드 **`ConnectivitySSID`**, **`ConnectivityPSK`**와 `getAuthType()`(WPA2_PSK → 2)을 읽어 `doSendAccessoryConfigurationInformation`을 호출합니다. 인자는 SSID, 비밀번호, 보안 방식, 채널 4개입니다.
  - **채널은 늘 0이고 "있음" 표시도 false라서 실제로는 보내지 않습니다**(smali: `channel` = 0, `if-lez`면 플래그 0). iPhone은 SSID로 스캔해 찾으므로, 대역(2.4/5GHz)과 채널은 iAP2와 무관합니다.
  - **핫스팟이 켜져 있는지(`isWifiApEnabled`)는 검사하지 않습니다.** `ieee80211_frequency_to_channel`은 있지만 호출되지 않습니다.
- 블루투스 전송 데이터 입력(`Iap2SvcTransportReadDone`)을 호출하는 순정 코드가 iAP2 서버·라이브러리 밖에 없습니다. 미국판과 같은 상황이라 HMG-API 브리지가 필요합니다.
  - 순정의 SPP API는 있습니다: Broadcom `HfDeviceBTCMManager.IbtcmSppConnect` 등. PhoneProjection이 SPP 연결을, GPM이 안드로이드 오토용 SPP 수신을 씁니다.

## 5. 순정 핫스팟 설정(`WifiApConfigStore`, framework)

- 파일: `/data/misc/wifi/softap.conf`. 기능 `com.hkmc.software.security.unece`가 있으면 `/securedata/wifi/softap.conf`로 바뀌고 비밀번호가 TSM으로 암호화되는데, 이 차에는 해당 기능이 없습니다.
- 형식 3: `int 3, UTF SSID, UTF ConnectivitySSID, int authType, UTF PSK, UTF ConnectivityPSK, int channel, int channel24GHzBand, boolean is24GHzBand, UTF vendorSpecific, int apMode`
- 기본값:
  - `ConnectivitySSID`: `Kia_` + 무작위 4글자
  - 비밀번호: 무작위(특수문자 포함)
  - 5GHz 채널: `WIFI_AP_5G_CHANNEL_149`
  - `vendorSpecific`: `getDefaultCarPlayIE()`가 만든 카플레이 IE(16진 문자열)
- `NetworkManagementService.startAccessPoint`는 netd에 `softap set <if> <ssid> broadcast <ch> <sec> <key>`만 보냅니다. Java 쪽에서는 IE를 넘기는 경로가 없습니다.
- `com.hkmc.software.wifihotspot`은 순정 Wi-Fi 스택(`WifiStateMachine`, `WifiService`, Wi-Fi 설정 앱)만 검사합니다. 카플레이 쪽(DiPO, iAP2, BT)은 검사하지 않으므로 이 차에서는 켜지 않습니다.

## 6. DiPO(`com.daudio.app.dipo`)

- `i/e.isSupportWirelessCarPlay()`: `carplay_wireless` 기능 && `nP`. `nP`는 `PhoneProjection.CP_FIRST_CONNECTED` 수신 시 설정됩니다. HMG-API 훅 `dipo.utils.is_support_wireless_carplay`가 대체합니다.
- DiPO와 GPM은 `wlan0`이나 `getWifiApConfiguration`을 직접 쓰지 않습니다. GPM은 `wlan0`과 핫스팟 설정을 참조합니다(안드로이드 오토 무선용).

## 7. 라이브러리 시그니처(모드 스텁과 대조)

- Broadcom `com.broadcom.bt.jar`: `IbtcmGetHfpConnectedDevice()`, `IbtcmIsSppConnectedDevice(String)`, `IbtcmSppConnect(String)`, `IbtcmSppOutPutStreamWrite(String,byte[])`, `registerHfDeviceStatusListener(...)`, `HfDeviceStatusListener`의 3개 콜백 → **모두 일치**
- TCC `com.tcc.iap2`: `IIap2Service.Iap2SvcInit(IIap2Listener,Iap2ListenerInfo)`, `Iap2SvcTransportReadDone(byte[],int)`, `IIap2Listener.connected/disconnected/notify`, `Iap2ListenerInfo.onSetSupportType/onSetListenerName`, `Iap2NotiMsg` 접근자 → **모두 일치**

## 8. HMG-API 훅 맵

- `tools/map-car.py`(baksmali 2.5.2) 결과: 11개 앱에서 283개 지점 매핑, 68개 없음(버튼 설정·런처 등 코어 부가 기능).
- **무선 모드가 선언한 36개 지점과 코드가 이름으로 찾는 16개, 총 52개가 모두 매핑됨.**
- 수집 당시 Leafia 기본 모드가 설치돼 있었지만 앱·라이브러리·프레임워크는 원본입니다. Leafia가 바꾼 것은 `featurexml.cfg`, 권한 파일, `build.prop`입니다.

## 9. 차량 밖 검증

- 가상 루트(국내형 순정 파일, Leafia 변경 되돌림)에서 HMG-API 엔진을 실행한 결과:
  - `SystemCheck`: `ok: wireless-carplay-kr supports this unit`
  - `map`: 이 맵이 선택됨(차량 검증 전에는 훅 꺼짐 = 정상)
  - `plan`/`apply`: `featurexml.cfg` 29번째 줄만 주석 처리, `carplay_wireless.xml` 추가, 설정값 3개
  - `restore`: `featurexml.cfg`가 원본과 바이트 단위로 같아지고 권한 파일도 제거됨
- `tests/apsync-test.sh` 17항목 통과(dash, bash POSIX):
  - SSID·비밀번호 반영(특수문자 왕복 포함), 5GHz 149, 나머지 줄 유지
  - 재시작 요청, 두 번째 실행 무변경, 중복 키 정리
  - STA 모드 무시, 제거 시 원본 파일 복원, 로그 비밀번호 마스킹

## 10. 참고: 무선 ADB

`sys.usb.config=host`(adb 없음) 상태에서 adbd를 직접 띄우면 첫 연결 뒤 접속 인사(CNXN)에 응답하지 않았습니다. 수신 큐에 데이터가 쌓인 채로 멈춥니다.
HMG-API `adb` 모드처럼 `sys.usb.config=host,adb` + `persist.adb.tcp.port=5555`를 쓰는 것이 맞아 보입니다.
엔지니어링 모드의 ADB TCP 스위치(`persist.service.adb.tcp.enable`)는 `eth0`를 `192.168.0.123`으로 올립니다. 동글 AP가 `192.168.0.x` 대역이면 충돌하므로 쓰지 않습니다.

## 11. 첫 차량 시험 (0.1.0)

2026-11-07 22:04, `usb/trylog` 수집.

| 단계 | 결과 |
|---|---|
| 설치·적용 | 두 패키지 설치, 모드 적용(설정값 3개, `featurexml` 29번째 줄, 권한 파일). 차량에서 만든 맵 `probed` + 검증 통과 |
| 블루투스 | iPhone 연결, SPP 열림(`HfDeviceBTCMSppApi`, `onBTCMSppStatusChanged`) |
| 브리지 | **동작 안 함**: `mods: wireless-carplay-kr not loaded: hook point btsettings.projection_helper.open_wireless_page isn't mapped on this car (0 methods match in com.android.settings2.bluetooth.iP)` |
| 핫스팟 동기화 | **실패**: 순정 값(`Kia_xxxx`, 12자, 5GHz 149)은 읽었지만 `can't write …/hotspot.conf` → 핫스팟은 계속 `HKG_USB_Hotspot` |

원인과 0.1.1의 수정:

1. **훅 미로드**: HMG-API의 차량 탐색기(`MapProbe`)가 국내형 BtSettings에서 `projection_helper`를 `iO` 대신 `iP`로 잡아 4개 지점이 빠졌습니다(Mac에서 같은 결과 재현). 모드는 지점 하나만 빠져도 훅 전체가 꺼집니다.
   - 수정: 해당 지점을 쓰는 메뉴 기능(미국·캐나다 전용)을 모드에서 뺐습니다. 남은 35개는 차량 탐색기 결과에 모두 있습니다.
2. **동기화 실패**: Android 4.4 toolbox `mv`는 옵션을 받지 않아 `mv -f`가 실패했습니다. 백업 파일도 같은 이유로 남지 않았습니다.
   - 수정: `mv`로 바꾸고, 시험에 toolbox식 `mv`를 넣어 다시 생기면 잡히게 했습니다.
3. **인터페이스 이름**: 동글을 뺐다 꽂으면 AP가 `rtwlan0`/`rtwlan1`/`rtwlan2`로 바뀝니다(데몬 로그).
   - 수정: 3절의 1바이트 기본값 패치로 바꾸고, 브리지도 `rtwlan*` 전체를 봅니다.
4. **진단 로그 과다**: 전체 logcat이 초당 약 60KB라 11개 파일(1MB, `-n 4`인데도 10개까지 순환)에 2분 30초만 남았습니다.
   - 수정: 카플레이·iAP2·블루투스·핫스팟 태그는 전부, 나머지는 경고 이상만 남깁니다(같은 로그 기준 약 7%).

## 12. 두 번째 차량 시험 (0.1.1)

2026-11-07 22:16~22:19. iPhone에 카플레이가 잠깐 떴다가 사라졌습니다.

| 시각 | 단계 | 결과 |
|---|---|---|
| 22:16:45 | USB 핫스팟 | `Kia_xxxx`, 5GHz 149, `rtwlan0` |
| 22:17:15 | 모드·브리지 | 모드 로드, SPP 연결 → `BT_ATTACHED` → iAP2 블루투스 세션(`comp=4`) |
| 22:17:16~17 | iAP2 | 인증(`IdentificationAccepted`), **Wi-Fi 정보 전달**(`doSendAccessoryConfigurationInformation() ssid : Kia_xxxx`) |
| 22:17:19~20 | 카플레이 | `TccCarPlay_Create` → `TccCarPlay_Start`, AirPlay 서버(7000), Bonjour `_airplay._tcp`, `CarPlayControlClientStart` |
| 22:17:26 | **DiPO** | `displayConnectionError()` → `resetUSB()` → `reset Usb DolPhin isOff [true]`(`sys.usb.vbus_ctrl` off/on) → `USB_DEVICE_DETACHED` |
| 22:17:29~31 | 동글 | USB 분리 후 재인식, `rtwlan1` 생성(`link is not ready`). 데몬은 핫스팟을 다시 띄우지 않음 |
| 22:17:30~32 | 폰 프로젝션 | 순정 첫 연결 팝업 → OK(`CP_FIRST_CONNECTED`) |
| 이후 | | 카플레이 세션 없음, AirPlay 서버는 대기 상태 유지 |

원인과 0.1.2의 수정:

1. **DiPO의 USB 리셋**: 블루투스 카플레이 세션을 USB 아이폰처럼 다루는 흐름이라, 약 6초 안에 세션이 없으면 유선용 복구로 USB 전원을 껐다 켭니다(`DipoService.cv`/`F`: `sys.usb.vbus_ctrl`, `bP`/`cw`: MICOM `requestVBusOffOn()`). 미국 차는 Wi-Fi가 SDIO라 영향이 없지만, 이 차는 동글이 그 포트에 있습니다.
   - 수정: DiPO 프로세스에서 `SystemProperties.set("sys.usb.vbus_ctrl", …)`와 `ISystemService$Stub$Proxy.requestVBusOffOn()`을 동글이 있을 때만 건너뜁니다. 이름이 바뀌지 않는 API라 난독화 이름에 묶이지 않습니다.
   - DiPO는 오류 뒤에도 카플레이 인스턴스를 지우지 않았으므로(7000 대기 유지), 리셋만 막으면 됩니다.
2. **`libCarPlayCoreUtils` 패치 미적용**: 모드 Java가 패치할 라이브러리를 이름으로 요청하는데 이 라이브러리를 빠뜨렸습니다(`Dipo.start`).
   - 수정: 요청 추가.
3. **USB 핫스팟 미복구**: 동글이 2초 만에 다시 잡혀서 데몬이 분리를 감지하지 못했습니다. hostapd는 사라진 `rtwlan0`에 남았고, `rtwlan0`과 `rtwlan1`이 같은 `192.168.43.1/24`를 가졌습니다.
   - 수정: 동기화 서비스의 감시 기능이 사라진 인터페이스 주소를 지우고 재시작을 요청합니다.
4. 참고: Bonjour 검색(`BonjourBrowser_Start(…, "_carplay-ctrl._tcp", "local.", 인터페이스 0, …)`)은 모든 인터페이스를 봅니다. 인터페이스 이름 제한은 없습니다.
5. 안드로이드 오토 라이브러리 패치 요청(레시피 없음)이 매 부팅 오류를 남기던 것을 뺐습니다.

## 13. 세 번째 차량 시험 (0.1.2)

2026-11-07 22:34.

| 시각 | 결과 |
|---|---|
| 22:34:08 | USB 리셋 차단 훅 2개 설치(`sys.usb.vbus_ctrl`, `requestVBusOffOn`) |
| 22:34:45 | `libCarPlayCoreUtils.so: carplay-coreutils-usbwifi: applied`(0.1.1에서 빠졌던 패치 적용됨) |
| 22:34:46~50 | 브리지 → iAP2 인증 → Wi-Fi 정보(`Kia_xxxx`) → `TccCarPlay_Start`, AirPlay 서버·Bonjour |
| 22:34:55.6 | iPhone의 블루투스 통화(HFP) 연결이 끊겼다 다시 붙음 (카플레이로 넘어가는 동작으로 보임) |
| 22:34:56.09 | **`HANDLER_MESSAGE_CHECK_CONNECTION_ERROR` → `resetUSB()` → `reset Usb DolPhin isOff [true]`**(시작 6.0초 뒤), 22:34:56.10 동글 분리 |

원인과 0.1.3의 수정:

- **차단이 동작하지 않은 이유**: 차단 조건인 "동글 연결 여부"를 `/sys/class/net/rtwlanN/device`로 판정했는데, `usbwifi.hotspot`의 드라이버 빌드가 `SET_NETDEV_DEV`를 일부러 빼서(분리 시 안전성) 이 링크가 없습니다. 그래서 항상 "동글 없음"으로 판정했고, 조건이 거짓일 때는 로그도 남기지 않았습니다.
  - 수정: Realtek USB 드라이버(`/sys/bus/usb/drivers/rtl*`)에 묶인 USB 인터페이스(`4-1:1.0` 등)로 판정합니다. 리셋 요청은 막든 통과시키든 항상 로그를 남깁니다.
- **같은 이유로 동기화 서비스의 핫스팟 감시도 동작하지 않았습니다.**
  - 수정: 같은 드라이버 바인딩으로 동글을 판정하고, 데몬과 같은 규칙(가장 큰 ifindex의 `rtwlan`)으로 현재 인터페이스를 고릅니다. 복구할 때는 다른 `rtwlan`의 주소만 지웁니다(인터페이스는 끄지 않음).
- 로그 수집 USB: `device` 링크 대신 ifindex와 드라이버 바인딩을 기록하고, 커널 로그는 USB 허브·과전류 메시지까지 넓게 남깁니다.

## 14. 네 번째 차량 시험 (0.1.3)

2026-11-07 22:45~22:48. 사용자: "iPhone에서 `Kia_xxxx`에 붙었다 안 붙었다 하고, 직접 연결하면 비밀번호를 묻는다. 입력하니 잠시 정상 연결됐다가 곧 끊겼다."

| 시각 | 결과 |
|---|---|
| 22:45:52 | 카플레이 서버 시작 |
| 22:45:58 | `USB power reset (sys.usb.vbus_ctrl off/on) skipped` — **USB 리셋 차단 성공**, 핫스팟은 뽑을 때까지 유지 |
| 22:46:09~22:47:12 | iPhone(`..a5:cc`) 접속 → **정확히 6초 뒤 해제**를 7번 반복, WPA 인증 완료 없음 |
| 22:47:40 | 비밀번호를 직접 입력한 뒤 WPA 인증 완료, DHCP `192.168.43.12` |
| 22:47:41~48 | 헤드유닛이 Bonjour로 iPhone의 `_carplay-ctrl` 발견(`interface(rtwlan0)`) → 제어 연결 → AirPlay 접속(`fe80::…%rtwlan0`, IPv6 링크로컬 정상) → `pair-verify`(처음 보는 기기) → `pair-setup` |
| 22:47:49~ | 다른 주소(`..c2:d1`)가 "접속 후 6초 해제"를 반복하고, `..a5:cc`도 끊겼다 붙기를 반복 |
| 22:48:27 | AirPlay 연결 시간 초과(110) |

판단:

- 같은 iPhone이 **카플레이가 iAP2로 받은 설정으로는 WPA 인증에 실패**하고, 같은 비밀번호를 직접 입력하면 성공합니다.
- 직접 입력한 설정과 카플레이 설정이 같은 SSID를 두고 엇갈리며 연결이 흔들린 것으로 보입니다.
- 확인한 것: iAP2는 `ConnectivitySSID`/`ConnectivityPSK`/보안 방식 2를 보내고 채널은 보내지 않습니다(`doSendAccessoryConfigurationInformation(String,Z,String,Z,I,Z,I)`).
  - `decryptPSK`는 암호화 기능이 없으면 그대로 반환합니다.
  - `WifiConfiguration` Parcel은 `ConnectivityPSK`를 포함합니다(오프셋 @12).
  - USB 데몬(2.0.2, 저장소와 같은 해시)은 `wpa_passphrase=$AP_PASS`를 그대로 씁니다.
- 순정 비밀번호 생성기는 기호(`!"#$%&'()*+,-./:;<=>?@[\]^_{}~`)를 섞습니다. iAP2 네이티브 전송이나 iPhone 쪽에서 기호가 깨질 가능성이 가장 높다고 보고 0.1.4에서 영문·숫자로 바꿨습니다.

0.1.4의 수정:

- **동기화 서비스**: 순정 카플레이 설정을 iAP2와 같은 `IWifiManager.getWifiApConfiguration()`(바인더, root)으로 읽습니다. 파일과 다르면 기록합니다.
  - 비밀번호에 영문·숫자 외 문자가 있으면 `setWifiApConfiguration()`으로 영문·숫자 12자리(대·소문자·숫자 포함, 헷갈리는 글자 제외)로 바꿉니다.
  - 원래 값은 `/data/nemesis/backup/ev6kr.usbap.sync/projection.psk`(600)에 두고 제거 시 복원합니다. `.keeppsk` 파일로 끌 수 있습니다.
- **모드(iAP2 프로세스)**: `doSendAccessoryConfigurationInformation`에 넘어가는 값을 기록합니다. SSID, 비밀번호 길이, 기호 개수, `softap.conf`와의 일치 여부, 보안 방식, 채널만 남기고 비밀번호 자체는 남기지 않습니다.

## 15. 다섯 번째 차량 시험 (0.1.4)

**무선 카플레이 세션이 처음으로 성립했습니다.** 화면은 매우 느리고 계속 멈췄습니다.

- 인증 실패의 원인은 기호가 아니었습니다. iAP2가 보낸 비밀번호는 영문·숫자 12자였고 `softap.conf`와 같았습니다.
  - 실제 원인은 iPhone에 남아 있던 예전 Wi-Fi 프로필과 차량 프로필이었습니다. 둘 다 지운 뒤 붙었습니다.
- 세션 1 (23:08): `CarPlay session created (usb=false)`, `AirPlay session started … T=WiFi`, iAP2가 카플레이 채널(comp=5)로 넘어갔습니다.
  - 23:08:14.33 `StartScreenStream` → 14.42 `Received only SPS/PPS` → 25.74 `screen stream timeout - body` → 화면 스트림 중지.
- 헤드유닛 재부팅 (23:09:56~23:10:13): 로그에 크래시나 전원 이벤트는 없었습니다.
- 세션 2 (23:10:56, 재부팅 후): 세션은 곧바로 성립했습니다.
  - 23:11:02.75 `StartScreenStream` → 03.26 `Received only SPS/PPS` → 03.47 `screen stream timeout - body`.
  - 세션 자체는 23:11:45에 동글을 빼서 끝났습니다(`Reason=-6753`, 연결 끊김).
- 즉, 첫 화면 프레임의 본문(IDR 프레임, 수십~수백 KB)이 제때 도착하지 않습니다.
  - 작은 메시지(iAP2, SPS/PPS, 핑)는 오갑니다. 큰 연속 데이터만 막힌다는 뜻입니다.
- 두 번째 부팅의 `rtwlan0` 카운터: 받음 2358패킷, 5.08 MB, **drop 12368**.
  - 평균 2155바이트/패킷이라 A-MSDU(즉 QoS/HT)가 쓰였을 가능성이 있습니다.
  - Realtek 드라이버의 `rx_drop`은 관리 프레임(이웃 AP 비컨 등), 중복(재전송) 프레임, 순서 재정렬 탈락, 복호 실패를 모두 셉니다. 커널 backlog 초과(`netif_rx`)도 여기에 더해집니다.
  - 그래서 이 숫자만으로는 원인을 가를 수 없습니다.
- USB 패키지의 설정:
  - 드라이버는 `rtw_en_napi=0 rtw_en_gro=0`으로 올라가므로 받은 프레임이 모두 `netif_rx` 백로그(기본 1000)를 거칩니다.
  - `hostapd.conf`에는 `ieee80211n=1`만 있고 `wmm_enabled`, `ht_capab`, `ieee80211ac`가 없습니다. 쓰는 hostapd는 순정 `/system/bin/hostapd`(경로 문자열만 바꾼 사본)입니다.
  - hostapd 버전에 따라 WMM이 꺼진 채로 동작할 수 있습니다. 그러면 HT 집합 전송(A-MPDU)을 못 쓰고 HT20, 짧은 GI 없음, VHT 없음이 됩니다.

0.1.5 (진단 + 안전한 조정):

- **수신 backlog**: 서비스 시작 시 `net.core.netdev_max_backlog` 1000→5000, `netdev_budget` 300→600으로 올립니다. 처음 값을 백업하고 제거 시 되돌립니다.
- **네트워크 샘플러** (디버그 로그가 켜져 있을 때): `/data/nemesis/ev6kr.usbap.sync.netsample.txt`(+`.1`)에 기록합니다.
  - 5초마다: `rtwlan` 카운터, `softnet_stat`(2열이 backlog 초과), `snmp` Tcp/Udp, load.
  - 30초마다: 드라이버의 단말별 정보(`all_sta_info`: qos/ht/vht/집합 전송/속도, `rx_stat`·`rx_logs`의 drop 사유, `rx_signal`), `TcpExt`, 연결된 TCP의 송수신 큐와 재전송, DHCP 클라이언트로 핑(56, 1400바이트).
  - 동글은 trylog USB를 꽂을 때 빠지므로 `/proc/net/rtl*`은 동글이 꽂혀 있는 동안 서비스가 기록합니다.
- **trylog 2**: 위 파일, `net-now.txt`(softnet/snmp/netstat/sysctl), hostapd 버전과 설정(비밀번호 가림)을 모읍니다.

다음 실험 후보 (USB 패키지 `usbwifi.hotspot` 쪽, 결과를 보고 결정):

1. `hostapd.conf`에 `wmm_enabled=1` (모든 hostapd가 지원, 위험 낮음)
2. `ht_capab=[SHORT-GI-20]` → 이후 `[HT40+][SHORT-GI-40]`
   - 드라이버가 알리지 않는 능력을 적으면 hostapd가 시작하지 않으므로 하나씩 시험합니다.
3. `rtw_en_napi=1 rtw_en_gro=1`. `softnet_stat` 2열이 늘 때만 해당합니다.
4. `ieee80211ac=1` + VHT80. 순정 hostapd가 `CONFIG_IEEE80211AC` 없이 빌드됐으면 알 수 없는 항목으로 시작이 실패하므로 버전을 먼저 확인합니다.

0.1.6: 업데이트할 때 핫스팟 이름이 바뀌지 않게 했습니다.

- NEMESIS는 업데이트할 때 옛 버전의 `preuninstall`을 실행합니다. 그 스크립트가 USB 패키지 원래 SSID(`HKG_USB_Hotspot`)를 되돌리고, 새 버전의 `postinstall`이 곧바로 `Kia_…`로 다시 바꿨습니다.
  - 그 결과 핫스팟이 두 번 재시작했고, iPhone 목록에 두 이름이 함께 보였습니다.
- 이제 `preuninstall`은 새 버전이 `/data/local/tmp/nemesis/stage/<id>/NEMESIS.data`에 풀려 있으면 업데이트로 봅니다.
  - 업데이트로 보면 핫스팟 설정, 비밀번호, `net.core` 값, 백업, 플래그를 그대로 둡니다.
  - NEMESIS가 훅에 업데이트 여부를 따로 알려주지 않아서 이 방법을 씁니다.
- 0.1.5에서 0.1.6으로 올릴 때는 옛 0.1.5 스크립트가 돌기 때문에 한 번 더 바뀝니다. 이후 업데이트부터 적용됩니다.

## 16. 여섯 번째 차량 시험 (0.1.6, 23:45)

세션은 이번에도 성립했지만(`T=WiFi`, 66초), 결과는 같았습니다.

- 23:45:40.77 화면 스트림 시작 → 41.30 `Received only SPS/PPS` → 41.55 `screen stream timeout - body` → 화면 중지.
- 오디오(UDP)도 늦게 도착했습니다. 늦은 패킷 폐기가 최대 1020 ms였고, 세션 종료 시 `88 lost, 53 late`가 기록됐습니다.

샘플러(0.1.5)로 원인의 범위가 좁혀졌습니다.

| 항목 | 값 | 뜻 |
| --- | --- | --- |
| `softnet_stat` 2열 (커널 backlog 초과) | 0 | 커널 대기열은 원인이 아님 |
| iPhone 연결 상태 (`all_sta_info`) | `qos_en=1 ht_en=1`, A-MPDU 사용, HT20, 짧은 GI 없음, VHT 없음 | WMM·HT는 이미 켜져 있음 (hostapd v2.6-devel이 HT와 함께 WMM을 켬) |
| 신호 (`rx_signal`) | -34 ~ -37 dBm | 매우 강함 |
| iPhone → 동글 속도 (`sta_tp_info`, `rx_per_rate_cnt`) | 대부분 **MCS0** (75798건), 다음이 MCS8 (22040건) | 신호가 강한데도 가장 낮은 속도 |
| 받은 데이터 프레임 / 중복 / 재정렬 창보다 오래된 프레임 | 20921 / **2972** / **16528** | iPhone이 이미 받은 프레임을 계속 다시 보냄 |
| 동글 → iPhone 재전송 (`tx_stat`) | 1499건 중 retry 1244, 실패 89 | 반대 방향도 재전송이 많음 |
| 다른 단말 (`fa:af:…`, 같은 핫스팟) | 받은 503 / 중복 1307 | iPhone만의 문제가 아님 |
| 핑 (세션 중, iPhone) | 평균 1.2초, 최대 1.9초 | 링크 전체가 밀려 있음 |
| 실효 수신량 (`rtwlan0`) | 1분 남짓에 9.6 MB (약 1 Mbps) | |
| 세션 중 TCP | `192.168.43.1:6030` ← iPhone, 수신 큐 203 KB | 화면 스트림이 멈춘 뒤 읽히지 않은 영상 |

해석:

- 단말이 이미 받은 프레임을 계속 다시 보낸다는 것은 **동글의 ack/block ack가 단말에 닿지 않는다**는 뜻입니다. 두 단말 모두 그렇습니다.
- 그래서 iPhone은 속도를 최저(MCS0)로 내리고 같은 프레임을 여러 번 보냅니다. 실효 속도가 약 1 Mbps, 지연이 1초 이상이 됩니다.
- 화면의 첫 IDR 프레임(수십~수백 KB)이 TCC 수신부의 짧은 대기시간 안에 오지 못해 화면 스트림이 끊깁니다.
- 원인 후보:
  - 동글의 A-MPDU block ack 처리 (드라이버 cilynx rtl88x2bu v5.8.7.1)
  - 채널 149(5.8 GHz 대역)와 국가코드 미설정(`chplan 0x7F`, `country unspecified`)에 따른 송신 설정
  - 동글 송신부 자체 (전원, 안테나)

0.1.7:

- **block ack 끄기 (기본값, 실험)**: 동글 드라이버의 `/proc/net/rtl88x2bu/rtwlanN/rx_ampdu`에 `0`을 써서 iPhone의 A-MPDU 세션을 받지 않게 합니다.
  - 이 드라이버의 `rtw_rx_ampdu_apply`는 AP 모드에서 연결된 단말에도 바로 적용됩니다.
  - 3초마다 확인하므로 동글을 다시 꽂아도 다시 적용됩니다. 제거 시 `255`(드라이버 자동)로 되돌립니다.
  - 집합 전송이 없어도 HT20 최대 속도에서 20~40 Mbps가 나와 카플레이(5~15 Mbps)에는 충분합니다.
- **조정 파일** `/data/nemesis/ev6kr.usbap.sync.tune`:
  - 항목: `rx_ampdu=0|auto`, `channel=36…48|149…165`, `country=KR`
  - trylog 스틱의 `EV6KR-TUNE.txt`가 이 파일로 복사되고, `EV6KR-TUNE-RESET`이 있으면 기본값으로 돌아갑니다.
- **버그 수정**:
  - `/proc/sys` 값을 `read`로 읽어 첫 바이트만 백업됐습니다(1000 → "1", 300 → "3"). 이제 `cat`으로 읽습니다.
    - 값이 이상하면 제거 시 커널 기본값으로 되돌립니다.
    - 0.1.5에서 0.1.6으로 업데이트할 때 옛 `preuninstall`이 잠깐 1과 3을 썼습니다. 0.1.6 서비스가 바로 5000/600으로 다시 썼고, 재부팅하면 어차피 초기화됩니다.
  - 샘플러 핑은 ARP에 있는 단말로 보내고 요약 줄을 온전히 남깁니다.
  - trylog는 모바일 데이터 DHCP 임대 파일(바이너리)을 더 이상 모으지 않습니다.

다음 단계:

- block ack를 꺼서 MCS가 오르고 중복이 줄면 원인이 확정됩니다.
- 그대로면 `channel=36` → `country=KR` 순서로 시험합니다.
- 그래도 그대로면 동글(칩·드라이버)의 AP 모드 한계입니다. RTL8851BU 등 다른 동글을 검토합니다.

### 동글 드라이버 빌드 검토 (usbwifi.hotspot, 2026-11-08)

- 소스: `cilynx/rtl88x2bu` v5.8.7.1 (2019, 지금은 유지보수되지 않음). 펌웨어와 RF 보정 코드가 드라이버에 들어 있으므로 이것도 2019년 것입니다.
  - 후속인 `morrownr/88x2bu`(v5.13.x)가 유지되고 있지만, 지원 커널이 높아서 3.18용 빌드는 따로 손봐야 합니다.
- 커널: 차량의 커널 설정(`config_tcc803x.txt`: HZ=100, SMP, PREEMPT, DEBUG_SPINLOCK)을 그대로 써서 kernel.org의 3.18.24 소스로 빌드합니다.
  - Telechips/Android 소스가 아니므로 cfg80211·네트워크 구조체를 바꾼 패치가 있다면 어긋날 수 있습니다.
  - 지금까지 본 값(SSID, 채널, HT, WMM, 단말 정보)은 모두 정상이었습니다.
- HKG 패치: 핫플러그 안전, DHCP 포트 변환(67↔1067), 초기화 오류 전달, `SET_NETDEV_DEV` 제거, NAPI/GRO 기본 끔.
  - ack, 집합 전송, 속도, 송신 전력 경로는 건드리지 않습니다.
  - 커널 수신 대기열 초과가 0이었으므로 NAPI/GRO를 끈 것은 이번 증상과 무관합니다.
- 송신 전력 제한표: Makefile 기본값 `CONFIG_TXPWR_LIMIT_EN = n`이라 국가별 제한은 적용되지 않습니다. 채널 149라서 전력이 깎였을 가능성은 낮습니다.
- 증상은 무선 구간의 ack 손실입니다. ack는 칩의 하드웨어와 펌웨어가 만들므로, 드라이버가 영향을 준다면 펌웨어 버전, RF 보정, 집합 전송 설정을 통해서입니다.
  - 0.1.7의 샘플러가 `ver_info`, `drv_cfg`, `fw_info`, `target_tx_power`, `tx_power_by_rate`를 한 번씩 기록합니다.
  - RTL8831BU(`fofajardo/rtl8851bu` v1.19.10, 2024)는 이미 3.18용으로 빌드되어 있습니다. 칩, 펌웨어, 드라이버 계열이 모두 달라 가장 쉬운 비교 시험입니다.

### 동글 드라이버 v5.13.1 빌드 (2026-11-08)

- 원본: `morrownr/88x2bu-20210702` @ `418d71cc` (v5.13.1)
- 같은 Gen5W 패치를 옮겨서 3.18.24-tcc / GCC 4.7로 빌드했습니다. 경고 0, `vermagic` 일치, 데몬 인자와 USB ID도 모두 있습니다.
- 이 시험 빌드는 작성자의 로컬 작업으로만 했고 공개하지 않았습니다. 같은 v5.13.1을 우리 패치로 빌드하는 방법은 [driver/](../driver/)에 있습니다(GPL-2.0, usbwifi.hotspot 코드 미사용). 이 시험은 21절의 `drv_cfg` 문제 뒤 중단했고, 지금 구성은 usbwifi.hotspot 자체 드라이버(v5.8.7.1)를 씁니다.
- 시험은 기존 모듈을 그대로 두고 `modules/88x2bu_tcc803x.ko`를 추가하는 방식입니다. 지우면 원래대로 돌아갑니다.
- 새로 찾은 위험: v5.13.1의 ethtool `get_drvinfo`가 부모 장치 없는 wiphy를 그대로 따라가 패닉이 날 수 있습니다. 핫언플러그 패치로 `set_wiphy_dev()`를 뺐기 때문입니다. NULL 가드를 넣었습니다.
- 0.1.7의 trylog는 동작 중인 드라이버 버전(`/sys/module/88x2bu/version`)과 `insmod.log`를 기록합니다.

## 17. 일곱 번째 차량 시험 (0.1.7 + 드라이버 v5.13.1, 2026-11-08 08:07)

- 새 드라이버 `v5.13.1-20-gbd7c7eb9d`가 정상으로 올라왔고, 핫스팟과 세션도 성립했습니다(`T=WiFi`, 63초). 동글을 뺄 때 커널은 멈추지 않았습니다(`hal_init fail` 로그만 남음).
- 결과는 같았습니다. 08:07:39 시간 동기화 UDP가 3초 동안 응답 없음 → 42.37 화면 스트림 시작 → 42.63 `screen stream timeout - body`(0.26초) → 화면 스트림이 다시 시작되지 않음 → 08:08:36 iPhone이 연결을 끊음(`Time Sync RTT 4/844/72 ms`).
- 화면 스트림이 멈춘 뒤에도 포트 6030 수신 큐에 59 KB가 쌓였습니다. iPhone은 영상을 보내지만, 너무 늦게 도착합니다.

| 항목 | 6차 (v5.8.7.1, block ack 자동) | 7차 (v5.13.1, block ack 끔) |
| --- | --- | --- |
| 신호 (`rx_signal`) | -33 ~ -37 dBm | -25 ~ -43 dBm |
| iPhone → 동글 속도 | 대부분 MCS0 | 대부분 OFDM 6M, 가끔 MCS7/MCS15 |
| 받은 데이터 / 중복 | 20921 / 2972 (14%) | 8789 / 1269 (14%), 5087 / 359 (7%) |
| 재정렬 창보다 오래된 프레임 | 16528 | 0 (block ack를 껐으므로) |
| 중복 관리 프레임 | 263 | 2723 |
| 동글 → iPhone (`tx_stat`) | 1499건, retry 83%, 실패 6% | 4229건, retry 60%, 실패 6% |
| 실효 처리량 (`sta_tp_info`) | 242 ~ 622 kbit/s | 57 ~ 137 kbit/s |
| 핑 (iPhone) | 0% 손실, 평균 1.2초 | 0% ~ 93% 손실, 평균 7 ms ~ 1초 |

- 두 번째 Apple 기기(`fa:af:…`, 1x1, 무작위 MAC. Apple Watch로 보임)는 연결 중에 동글이 보낸 `EAPOL 1/4`를 네 번 연속 받지 못했고, deauth와 재연결을 반복했습니다.
- 해석:
  - 드라이버 세대(2019 → 2021), 펌웨어, block ack 설정을 모두 바꿨는데 같은 패턴입니다. **동글은 잘 듣는데 동글이 보내는 것이 상대에게 잘 닿지 않습니다.**
  - block ack를 끄면 프레임마다 ack가 필요해서 더 느려졌습니다. 0.1.8에서 드라이버 자동으로 되돌립니다.
  - BT 공존은 꺼져 있습니다(efuse `0xC1=0x01`, 3~5비트가 1이 아님). RFE type 3, 2T2R입니다.
  - 드라이버는 1스트림 프레임(ack, 관리 프레임, 레거시와 MCS0-7 데이터)을 **안테나 경로 A 하나로만** 보냅니다(`txpath_1ss:0x1`, `CONFIG_PATH_DIVERSITY`, 레지스터 `0x93c[31:20]=0x001`). 받을 때는 두 경로를 합칩니다.
  - 그래서 경로 A의 안테나나 연결이 약하면 수신은 멀쩡하고 송신만 나쁜 지금 증상과 맞습니다.
  - 또 하나의 후보는 USB 전원입니다. 2경로 송신 전류에 헤드유닛 포트 전압이 처지면 송신만 일그러집니다. 다만 짧은 프레임(EAPOL, 56바이트 핑)도 긴 프레임만큼 실패해서 가능성은 더 낮습니다.

0.1.8:

- block ack: 기본값을 드라이버 자동으로 되돌렸습니다(`rx_ampdu=auto`).
- **송신 경로 시험 (기본값 `txpath=cycle`)**:
  - v5.13.1 드라이버의 phydm 명령 `odm/cmd`의 `trxpath 1 3 3 <1|2|3>`으로 1스트림 프레임을 경로 A, B, 양쪽으로 바꿉니다.
  - 이 명령은 드라이버의 채널·대역폭·송신 전력 설정을 잠그므로, 바로 `trxpath 0`으로 풉니다. 경로 설정은 드라이버가 무선부를 다시 초기화할 때까지 유지됩니다.
  - 매번 `read_reg`로 `0x93c`를 읽어 확인하고, 드라이버가 되돌렸으면 다시 적용합니다.
  - 핫스팟에 iPhone이 보이면 A → B → 양쪽을 약 21초씩 3바퀴 돌립니다. 각 단계 끝에 iPhone에 핑(1000바이트 8개, 최대 3초)을 보내고 `tx_stat`를 기록합니다. netsample에는 phydm `bbinfo`(경로별 RSSI·SNR·EVM·CFO)를 남깁니다.
  - 끝나면 응답이 가장 많은 경로를 유지합니다(동점이면 드라이버 기본인 A). 동글을 다시 꽂으면 처음부터 다시 합니다.
  - 기록은 `apsync.log`의 `dongle TX path …` 줄입니다.
  - 구형 드라이버(v5.8.7.1)는 이 명령의 넷째 값을 다르게 해석하므로, `trxpath -h` 도움말로 확인한 뒤 v5.13.1에서만 씁니다.
- **송신 전력 (`txpower=1..6`)**: `tpc_settings`에 `1 <mB>`를 써서 모든 속도를 그만큼 낮춥니다. USB 전원 가설을 시험할 때 씁니다. 0이면 드라이버 값입니다.
- 조정 파일 항목: `rx_ampdu`, `channel`, `country`, `txpath=cycle|a|b|ab|driver`, `txpower=0..6`.

다음 단계:

- 한 경로(B 또는 양쪽)만 핑 응답이 뚜렷하게 많으면 → 경로 A 쪽 안테나나 연결 문제입니다. 그 경로를 고정하고 화면이 나오는지 봅니다.
- 세 경로가 모두 나쁘면 → `txpower=6`으로 전원 가설을 보고, 이어서 외부 전원 USB 허브, 다른 동글(RTL8831BU) 순서로 봅니다.
- 집에서 같은 동글을 PC에 꽂아 AP로 쓰고 iPhone으로 속도를 재 보면, 동글 문제와 차량 환경 문제를 바로 가를 수 있습니다.

## 18. 독립 구성: usbwifi.hotspot 없이 (2026-11-08)

기존 구성은 제3자 패키지 usbwifi.hotspot(GRT47/HKG_5W_USB_Wlan)이 드라이버, hostapd, DHCP를 맡고, 우리 apsync가 그 설정 파일을 고쳐서 재시작시키는 방식이었습니다. 이 방식에는 다음 문제가 있었습니다.

- usbwifi.hotspot은 GitHub에서 스스로 업데이트합니다. 6차 시험 직전(11-07 23:43)에도 v2.0.2로 바뀌었습니다.
- 설정 동기화, 강제 재시작, 데몬 감시 같은 우회 코드가 필요했습니다.
- LTE 공유가 켜져 있어 iPhone이 동글 링크로 인터넷을 쓸 수 있었습니다.
- 그 저장소에는 라이선스 파일이 없어서 코드를 가져다 쓸 수 없습니다.

HMG-API 모드는 root 서비스(`"services"`, 부팅 시 시작, 감시·재시작)와 방화벽 규칙(`"network"`)을 선언할 수 있습니다. 그래서 핫스팟을 모드 하나로 옮겼습니다.

- **`usb-hotspot-kr` 0.1.0** ([hotspot/](../hotspot/)): 드라이버 적재, 순정 hostapd(설정은 `softap.conf`에서 바로), 순정 dnsmasq(DHCP만, 67번 포트), 정책 라우팅 테이블 경로, 동글 분리·재연결 감시를 맡습니다.
  - 진단·튜닝 코드는 apsync에서 [shared/rtwlan.sh](../shared/rtwlan.sh)로 옮겨 두 구성이 함께 씁니다. apsync 소스는 0.1.9로 올렸고 동작은 0.1.8과 같습니다(빌드하지 않음).
  - usbwifi.hotspot이 설치돼 있으면 꺼져 있고, 다른 `88x2bu`가 올라와 있으면 재부팅을 안내합니다.
- **드라이버** ([driver/](../driver/), GPL-2.0): morrownr v5.13.1 + 새로 작성한 수정(AOA용 usbfs 차단, 뽑힌 동글 먼저 표시, ethtool NULL 가드, 빌드 옵션).
  - 넷디바이스는 정상적으로 등록·해제합니다. 그래서 재연결 때 인터페이스 이름이 늘지 않습니다(usbwifi.hotspot은 해제하지 않아 `rtwlan1`, `rtwlan2`…로 늘었음).
  - DHCP 포트 변환은 없습니다.
  - 빌드 결과: vermagic 일치, 경고 0, USB ID 32개(`0bda:b812` 포함).
- **카플레이 모드 0.1.6**: 두 구성의 hostapd pid를 모두 봅니다. 기존 구성에서도 그대로 동작합니다.
- **trylog 4판**: 독립 구성의 로그, 커널 설정(`/proc/config.gz`), `ip rule`, UDP 소켓, `iptables -S`를 모읍니다.
- **차량 밖 시험**
  - `tests/hotspot-test.sh` 17개, `tests/apsync-test.sh` 47개가 sh·dash·mksh에서 통과합니다.
  - HMG-API의 스크립트 검사(차량 명령 목록)를 통과했습니다.
  - HMG-API 엔진이 서비스 정의를 받아들였습니다. 방화벽 규칙은 `allow_network` 없이는 빠진다는 경고가 나옵니다.

차에서 확인할 것:
- 동글을 뺄 때 커널이 버티는지
- dnsmasq가 67번 포트에서 동작하는지
- 순정 방화벽이 `rtwlan`을 막는지(막으면 `allow_network` 필요)
- 이 드라이버를 지금 커널 설정(HKG 저장소의 `config_tcc803x.txt`)으로 빌드했으므로, 차에서 받은 `/proc/config.gz`로 다시 빌드해 비교할 것

## 19. 여덟 번째 차량 시험 (0.1.8, 독립 구성 0.1.0, 2026-11-08 12:57~13:12)

**0.1.8: 재부팅 반복**
- 12:57:19에 0.1.7 → 0.1.8 업데이트가 설치됐습니다. 12:57:37에 재부팅됐는데, NEMESIS 대화상자 직후라 사용자 재부팅일 수 있습니다.
- 이어서 12:57:45, 12:58:30, 12:59:15에 부팅했고, 앞의 두 번은 30~45초 만에 기록 없이 끊겼습니다.
  - 두 번 모두 핫스팟이 뜨고(usbwifi.hotspot, v5.13.1 드라이버) iPhone이 자동으로 붙어 카플레이 트래픽이 시작된 직후였습니다. 세 번째 부팅 기준으로 12:58:48 핫스팟, 12:58:50~55 TCP 연결 12회, 12:59:00 트래픽 멈춤, 곧 끊김.
  - 차량 커널은 `PANIC_TIMEOUT=5`(패닉 5초 뒤 재부팅)입니다.
- 0.1.7과 다른 점은 **block ack 기본값(0 → 자동)**뿐이었습니다. 송신 경로 시험은 아래 버그로 한 번도 돌지 않았습니다.
  - 0.1.7(block ack 거부)에서는 같은 드라이버가 몇 시간 동안 멀쩡했습니다.
  - 결론: **v5.13.1 드라이버는 AP 모드에서 iPhone의 A-MPDU(block ack) 수신이 시작되면 커널을 죽입니다.** 패닉 메시지는 아직 없습니다. 차량 커널에 `PSTORE_RAM`/`PSTORE_CONSOLE`이 있으므로 trylog 5판이 다음부터 이전 부팅의 커널 로그를 가져옵니다.
- 2분이 안 된 부팅이 3번 이어져 **HMG-API의 부팅 보호 장치**(zygote 래퍼, `hook/starts` ≥ 3)가 훅을 껐습니다.
  - 13:11 부팅의 logcat에는 HMG-API 기록이 하나도 없습니다. 카플레이 모드가 동작하지 않은 원인입니다.
  - 되돌리는 방법은 `/data/hmgapi/hook/starts`를 0으로 쓰는 것입니다(HMG-API Troubleshooting 문서).
- 송신 경로 시험 버그: `trxpath -h` 끝의 줄바꿈 때문에 phydm이 `-h`를 인식하지 못해 기능 확인이 늘 실패했습니다. phydm은 한 단어짜리 명령에서만 줄바꿈을 지웁니다.

**독립 구성 0.1.0 (13:00 설치, 13:11 부팅)**
- HMG-API 서비스는 돌았습니다(`EV6KR-USBAP: waiting for a USB Wi-Fi dongle`).
- 우리 드라이버는 부팅 11초에 올라갔지만, 동글은 9초에 이미 인식돼 있었습니다. 그 사이 동글이 응답하지 않게 됐습니다(`Chip id is undefined`, `halmac_init_adapter fail`). 그래서 인터페이스가 없었습니다.
  - usbwifi.hotspot은 부팅 4초에 드라이버를 먼저 올려 두고, 동글이 나타나는 순간 잡게 합니다(AOA 탐색보다 먼저).
- 동글을 뺄 때 커널은 멈추지 않았습니다(`USB disconnect` 뒤 정상).

**고친 것**
- 드라이버(patch 5): RX A-MPDU를 처음부터 거부합니다. srcversion `FA9124C6624C40A5191D5B2`.
- 공통 코드: `rx_ampdu=0` 기본값으로 되돌림, 송신 경로 시험은 `txpath=cycle`일 때만, `trxpath -h`는 줄바꿈 없이 보냄.
- usb-hotspot-kr 0.1.1
  - `start: boot`로 바꾸고 서비스 시작과 동시에 드라이버를 올립니다(동글보다 먼저).
  - 동글이 꽂혔는데 드라이버가 못 잡으면 약 12초 뒤 한 번 다시 붙이고, 그래도 안 되면 동글을 다시 꽂으라고 남깁니다.
  - hostapd 전에 A-MPDU 거부를 적용합니다.
  - 부팅 보호 장치가 걸려 있으면 로그에 남깁니다.
- apsync 0.1.9(기존 구성 예비용): block ack 거부(0.1.7과 같음), 송신 경로 시험은 선택.
- trylog 5판: 이전 부팅 커널 로그(pstore, last_kmsg), 훅 상태(`hook/starts`, `hmgapi-hook` dmesg), `EV6KR-HOOKS-RESET`으로 부팅 보호 장치 초기화.

## 20. 아홉 번째 수집 (독립 구성 0.1.1, 2026-11-08 13:38~13:41)

- 0.1.1의 서비스는 부팅 3초에 드라이버를 먼저 올렸습니다(의도대로). 동글이 나타나자 드라이버가 잡았고, 안드로이드 오토(GalReceiver)의 AOA 요청은 `startAccessory -ret:-9`로 거부됐습니다.
- **hostapd가 한 번도 뜨지 못했습니다**: `Could not open configuration file ... for reading`, `Could not open entropy file ... for writing`.
  - 순정 hostapd는 시작 직후 `wifi`(AID_WIFI 1010)로 권한을 낮춥니다. 설정 파일을 root 전용(600)으로 만든 것이 원인입니다.
  - 0.1.2: 설정 파일, entropy 파일, ctrl 폴더를 1010 소유로 바꿨습니다(설정 파일은 여전히 600).
- dnsmasq는 기록이 없었습니다. 디버그 logcat이 `dnsmasq` 태그의 정보 메시지를 거르고 있었기 때문입니다(`*:W`). 0.1.2부터 `dnsmasq:V`로 남깁니다.
- 마지막 부팅은 13:41:07 직후, 가동 35초 만에 끝났습니다. 핫스팟이 없어서 트래픽도 없었습니다. 새 부팅에서 스틱이 가동 14초에 인식된 것을 보면 **동글을 뽑는 순간 커널이 죽었을** 가능성이 큽니다.
  - 우리 드라이버는 뺄 때 넷디바이스를 정상 해제합니다. usbwifi.hotspot 빌드는 이 경로의 패닉을 막으려고 해제를 건너뛰는 방식이었습니다.
  - 13:11 부팅에서는 동글 시작이 실패한 상태(드라이버가 잡지 않음)였고, 그때 뽑았을 때는 멀쩡했습니다.
  - 확정하려면 패닉 로그가 필요합니다. pstore와 `/proc/last_kmsg`는 비어 있었습니다. 순정 BootReceiver가 이전 부팅 커널 로그를 DropBox(`SYSTEM_LAST_KMSG`, `APANIC_CONSOLE`)에 넣으므로 trylog 6판이 거기서 가져옵니다.
- 13:00~13:11 사이 0.1.0의 부팅 다섯 번은 핫스팟·인터페이스가 없던 상태였습니다. 사용자 재부팅이었는지는 로그로 가릴 수 없습니다.
- 부팅 보호 장치는 `starts` 10에서 0으로 초기화됐습니다.
- trylog 5판의 dmesg 필터에 커널 명령줄(차량 시리얼 번호 포함)이 섞였습니다. 6판에서 빼고, 수집하는 모든 커널 로그에서 `serialno`, `command line`, `SerialNumber` 줄을 거릅니다.

## 21. 재부팅의 진짜 원인: 샘플러의 `drv_cfg` 읽기 (2026-11-08 14:00)

- 독립 구성 0.1.1과 0.1.2의 재부팅 4번, 그리고 0.1.8의 재부팅 반복 모두 **서비스 시작 또는 인터페이스 생성 약 30초 뒤**였습니다. netsample이 처음으로 드라이버 `/proc` 항목을 한꺼번에 읽는 시점입니다.
  - 핫스팟이 없고 트래픽도 없던 부팅에서도 같았습니다.
- 각 부팅의 netsample 기록은 `-- /proc/net/rtl88x2bu/ver_info`(내용 한 줄), `-- /proc/net/rtl88x2bu/drv_cfg`(머리줄)에서 끊깁니다. **`drv_cfg`를 읽는 도중 커널이 죽었습니다.**
  - 드라이버 빌드(HKG의 v5.13.1 포팅, 우리 빌드)와 상관없이 같았습니다.
- 차에서 몇 시간 동안 멀쩡하던 0.1.7은 이 읽기가 들어가기 전 빌드였습니다(7차 시험 netsample에 `ver_info`/`drv_cfg`가 없음). 그 뒤 v5.13.1 작업 중 샘플러에 드라이버 단위 항목을 넣고 dist의 0.1.7을 같은 번호로 다시 빌드했습니다. 그래서 dist의 0.1.7을 다시 설치하자 재부팅이 계속됐습니다.
- 19절의 "A-MPDU 수신이 커널을 죽인다"는 판단은 근거가 약해졌습니다. 0.1.8의 재부팅도 같은 첫 샘플링 시점이었습니다. 다만 그 판단으로 넣은 block ack 거부 설정은 0.1.7(정상 동작)과 같은 상태라 그대로 둡니다.
- 독립 구성의 남은 문제: hostapd가 `Could not set channel for kernel driver`로 실패했고, 한 부팅에서는 안드로이드 오토의 AOA 요청이 동글에 실제로 들어갔습니다(usbwifi 빌드에서는 늘 즉시 거부됨). 그래서 보류합니다.

0.1.9 (기존 구성)
- 샘플러는 차에서 이미 무사히 읽힌 항목만 읽습니다(6차·7차 기록). 드라이버 버전은 `/sys/module`에서 읽고, `drv_cfg`·`ver_info`·`tx_power_by_rate`·`rx_logs`·`tx_logs`는 읽지 않습니다.
- block ack 거부(0.1.7과 같음). 송신 경로 기능은 조정 파일에서 켜지 않으면 phydm 명령을 하나도 보내지 않습니다.
- trylog 7판: DropBox의 부팅 기록(약 1,800개)을 더 이상 복사하지 않습니다. 6판이 몇 분씩 걸린 원인이었습니다.
- `usb/driver-reset/`: usbwifi.hotspot의 드라이버 덮어쓰기 파일(`modules/88x2bu_<platform>.ko`)을 지워 패키지 원래 드라이버(v5.8.7.1)로 되돌리고, 지금 올라와 있는 드라이버를 보고합니다.
- `drv_cfg`를 읽는 이전 빌드(apsync 0.1.7·0.1.8과 그 묶음, usb-hotspot-kr 0.1.0~0.1.2)는 `dist/withdrawn/`으로 옮겼습니다.

## 22. 열 번째 수집 (0.1.9, usbwifi 원래 드라이버, 2026-11-08 14:17): 검은 화면의 원인

- 재부팅은 없어졌고, HMG-API 훅이 켜졌으며(`hooks on, start 1`), 드라이버는 usbwifi.hotspot의 v5.8.7.1입니다.
- 14:17:35 무선 세션 성립(`T=WiFi`, IPv4 192.168.43.12) → 14:17:42.49 화면 스트림 시작 → **42.72 `screen stream timeout - body`(0.23초)** → 화면 중지(검은 화면) → 14:18:24 HTTP 읽기 시간 초과로 세션 종료.
- 링크는 이전보다 좋았습니다. 핑 손실 0%, 평균 3~42ms, 신호 -27dBm.
- **원인**(`libCarPlayCore.so`, `AirPlayReceiverSessionScreen_ProcessFrames`):
  - 프레임마다 헤더(128바이트)와 본문을 NetSocket으로 읽을 때 시간 인자로 특수값 `-65536`(`movs r7,#0; movt r7,#0xffff`, 0x1483a/0x14840)을 넘깁니다.
  - TCC의 `NetSocket_Wait`(`libCarPlayCoreUtils.so` 0x4b9e0)는 이 값을 **200ms**(`tv_usec 0x30d40`)로 바꿉니다.
  - 그래서 한 프레임을 받는 도중 200ms만 데이터가 끊겨도 `kTimeoutErr` → `screen stream timeout - body` → 화면 스트림을 멈춥니다.
  - 유선 USB에서는 이런 끊김이 없지만, Wi-Fi에서는 재전송 한 번이면 넘습니다(리눅스 TCP 최소 RTO 200ms).
- **모드 0.1.7**
  - 레시피 `carplay-core-screen-timeout`: `movs r7,#5; movt r7,#0`으로 바꿔 화면 프레임 읽기가 최대 5초를 기다리게 합니다.
  - HMG-API `lpatch`로 확인했습니다. 순정 `ef49c09b…`은 PATCHABLE, 적용 결과 `d7fe644a…`는 APPLIED.
  - USB 리셋 가드도 고쳤습니다. 14:17:16 DiPO의 VBUS 리셋이 아직 드라이버에 잡히기 전인 동글을 끊었기 때문에, 이제는 USB ID(RTL8812BU/8822BU/8831BU)만 보여도 리셋을 막습니다.
- 기대: 화면이 나오되, 링크 속도만큼 느리거나 끊길 수 있습니다. 링크 자체(동글 송신 쪽 손실)는 여전히 다음 과제입니다.

## 23. 열한 번째 수집 (모드 0.1.7, 2026-11-08 14:21~14:30): 화면이 나오다가 멈춤

- 화면은 나왔지만 끊기다가 멈췄고, 음악은 계속 나왔습니다.
- 세 세션 모두 화면이 20초, 1.7초, 7초 나온 뒤 `screen stream timeout - body`로 멈췄고 다시 시작되지 않았습니다. 세션(오디오)은 135초, 259초 이어졌습니다.
- **0.1.7의 화면 대기 패치는 적용되지 않았습니다.**
  - HMG-API는 라이브러리 하나에 적힌 레시피 가운데 그 빌드에 맞는 **첫 번째 하나만** 적용합니다(`ModContext.nativePatch`).
  - `carplay-core-wifi`의 `native ef49c09b…` 줄(국내형 v039은 Wi-Fi 세션을 원래 받음)이 먼저 맞아서, 뒤에 둔 `carplay-core-screen-timeout`은 실행되지 않았습니다.
  - 0.1.8에서 순서를 바꿨고, 0.1.7은 `dist/withdrawn/`으로 옮겼습니다.
- 그래서 "멈춤"은 이번에도 200ms 대기 때문이었습니다. 화면이 나오던 동안의 수신 속도는 5초 평균 0.6~3Mbit/s였고, iPhone은 MCS14~15로 보냈습니다. "끊김"은 이 처리량 탓으로 봅니다.
- 다음 실험(한 번에 하나씩)
  1. 모드 0.1.8: 멈춤이 사라지는지
  2. `rx_ampdu=auto`: v5.8.7.1 드라이버에서는 6차 시험 때 이 상태로 문제가 없었습니다. 0.1.8의 재부팅은 `drv_cfg` 읽기 탓이었습니다.
  3. 채널·대역폭: usbwifi.hotspot의 hostapd 설정은 HT20뿐입니다.
  4. 다른 동글(RTL8831BU 등)

## 24. 열두 번째 수집 (모드 0.1.8, 2026-11-08 15:05~17:33): 화면은 버티고, 링크가 끊김

- **화면 대기 패치가 적용됐습니다.** 부팅마다 `native patch libCarPlayCore.so: carplay-core-screen-timeout: applied`가 찍혔습니다.
- 사용자 관찰: 몇 초 되다가 끊김.

### 첫 시도 (15:08, block ack 끔)
- 15:08:02 세션 시작, 15:08:08 화면 시작.
- 15:08:13 iPhone이 연결된 상태에서 다시 접속(재결합)을 요청했습니다. hostapd의 4-way handshake가 4초 안에 끝나지 않아 15:08:17에 끊겼고, 15:08:19에 다시 붙었습니다.
- 다시 붙는 사이 iPhone이 AirPlay 연결을 끊어(ECONNRESET), 세션이 17초(화면 11초) 만에 끝났습니다.
- 15:07~15:09 동안 iPhone은 25~35초마다 재결합했습니다. 다른 Apple 기기(임의 MAC)도 같은 핫스팟에 붙었습니다.
- 재결합과 handshake 실패는 iPhone이 동글의 beacon·EAPOL을 놓친다는 뜻입니다(17절과 같은 송신 손실).

### 둘째 시도 (16:23, block ack 켬: 15:09에 스틱으로 `rx_ampdu=auto`)
- iPhone은 16:22:24에 붙어 16:31까지 재결합 없이 머물렀습니다.
- 16:23:25 세션 시작, 16:23:33 화면 시작. 화면이 **106초** 나왔습니다(끊김은 있었음).
- 16:25:14부터 화면 데이터가 멈췄고, 5초 뒤 16:25:19에 `screen stream timeout - body`가 났습니다. 대기 시간이 200ms에서 5초로 바뀐 것이 확인됩니다.
- 16:25:31 iPhone이 연결을 끊었고, 16:25:34 세션이 `-6753`(kConnectionErr)으로 끝났습니다. AirPlay 시각 동기 왕복은 최소/최대/평균 4/736/79ms였습니다.
- 화면이 나오던 동안 수신 속도(5초 평균)는 0.15~11.4Mbit/s, 대개 1.6~5.5Mbit/s였습니다. block ack를 끈 23절의 0.6~3Mbit/s보다 높습니다. TID 0, 2, 4에 block ack 세션(64)이 열렸습니다.
- 동글→iPhone 송신은 여전히 나빴습니다.
  - ping 손실: 화면이 나오던 동안 0~61%, 세션 뒤 86~100%
  - 재전송: 송신 2242건 중 retry 1300, 실패 89
  - 송신 속도: MCS4~6
  - 수신 신호: −34dBm
- 16:24:19~24에는 동글이 5초에 3381·2925패킷을 보냈습니다. 헤드유닛 자신의 TCP 출력은 839·1853이었으므로 약 2500패킷은 헤드유닛이 만든 것이 아닙니다.
  - usbwifi.hotspot은 LTE 공유(MASQUERADE 192.168.43.0/24 → rmnet+, DNS DNAT)를 켭니다. iPhone의 인터넷 트래픽이 이 경로로 동글의 약한 송신 방향을 함께 쓴 것으로 보입니다.
  - 샘플러가 포워딩 카운터를 남기지 않아 확정은 아닙니다.

### 판단
- 소프트웨어 쪽 장애는 해결됐습니다: 재부팅 없음, 훅 동작, 화면 대기 패치 동작.
- 세션을 끝내는 것은 **동글→iPhone 무선 송신**입니다. 트래픽이 없을 때도 손실되고, 6·7차(두 드라이버 모두)와 같은 양상입니다.
- 후보는 세 가지입니다.
  - 동글 하드웨어: 1-stream 프레임을 내보내는 경로 A의 안테나·급전
  - USB 전원: 송신 전류에서 전압 강하
  - 설치 위치
- 경로 A 가설은 소프트웨어로 시험할 수 있습니다. usbwifi.hotspot의 v5.8.7.1 드라이버에도 v5.13.1과 같은 `trxpath` 코드가 있습니다(`phydm_config_trx_path_v2`, `config_phydm_trx_mode_8822b` 동일, 입력 검사 한 줄만 다름).

### apsync 0.1.10 (trylog 8)
- **block ack 기본값을 드라이버에 맡김**(`rx_ampdu=auto`). 8차 재부팅의 원인은 `drv_cfg` 읽기였고, v5.8.7.1에서는 켠 상태로 문제가 없었으며 처리량이 높았습니다. 독립 구성은 드라이버를 차량에서 시험하기 전까지 거부를 유지합니다.
- **송신 경로 시험의 충돌 보호**
  - phydm 명령은 차량에서 처음 쓰는 드라이버 입력입니다. 여기서 커널 패닉이 나면 부팅 때마다 반복되고 HMG-API 부팅 보호에 걸립니다(`drv_cfg` 때처럼).
  - 경로를 바꾸기 전에 부팅 ID를 `<RT_BASE>.txp-guard`에 쓰고 sync합니다. 경로가 1분 동안 유지되면 이 파일을 지웁니다.
  - 다음 부팅에서 이전 부팅의 파일이 남아 있으면, 그 부팅이 경로를 바꾼 지 1분 안에 꺼진 것입니다. 이때 시험을 끕니다: 설정 파일에 `txpath=driver`와 `#txpath-off <날짜>`를 씁니다.
  - trylog 8은 `#txpath-off`가 있으면 스틱의 `EV6KR-TUNE.txt`에서 txpath 줄을 빼고 적용합니다. 다시 켜려면 `EV6KR-TUNE-RESET`을 함께 둡니다(RESET을 먼저 처리).
- trylog 8은 logcat 사본(`logcat-now.txt`, debug logcat)에서도 USB 일련번호 줄을 거릅니다. 7판까지는 커널 로그만 걸러서, logcat에 모뎀·USB 스틱의 일련번호가 남았습니다. Mac의 로컬 사본은 지웠습니다.
- 테스트: apsync 52개, 독립 구성 20개(sh, dash, mksh).

### 다음 실험 (한 번에 하나씩)
1. `txpath=cycle`(+`rx_ampdu=auto`): 카플레이를 연결한 채 약 4분. apsync 로그의 `dongle TX path` 줄에 경로마다 ping 응답 수가 남습니다.
   - 한 경로만 확실히 좋음 → 동글 안테나·급전 문제. 그 경로로 고정(`txpath=b` 등).
   - 모두 나쁨 → 전원(외부 전원 USB 허브), 위치(짧은 연장선으로 동글을 트인 곳에), 다른 동글(RTL8831BU: usbwifi.hotspot이 `8851bu` 드라이버도 올림).
2. 필요하면 USB 핫스팟의 LTE 공유 끄기(iPhone은 자기 모바일 데이터를 씀)

## 25. 열세 번째 시도 (apsync 0.1.10, 2026-11-08 19:34 전후): 핫스팟이 안 뜸, 로그는 비어 있음

- 사용자 관찰: 0.1.10 설치와 `txpath=cycle` 적용 뒤 핫스팟이 만들어지지 않는 것 같음. 새 동글(RTL8831BU)도 같음.
- 스틱의 `EV6KR-TRYLOG/`(19:34)는 파일이 모두 0바이트였습니다. 만들어진 파일은 `summary.txt`, `maps/`, `hmgapi-log*.txt`, `apsync*.log`, 첫 debug logcat 사본까지이고, 그 뒤(`usbwifi-daemon.log` 등)는 없습니다.
  - Android vold는 vfat를 `dirsync`로 올립니다. 파일 생성은 바로 기록되고, 내용은 나중에(스크립트 끝의 `sync` 또는 커널의 지연 쓰기) 기록됩니다.
  - 따라서 스틱은 trylog가 100번째 줄(첫 debug logcat 거르기)에 있을 때 빠졌습니다. trylog 8은 설정 파일을 맨 끝에서 적용하므로, **`txpath=cycle`은 적용되지 않았습니다.**
  - 장치에 남은 설정은 16:2x에 넣은 `rx_ampdu=auto`입니다. 0.1.10의 동작은 0.1.9 + `rx_ampdu=auto`(16:23에 핫스팟·세션이 된 조합)와 같고, phydm 명령은 보내지 않습니다(0.1.9 대비 차이는 crash guard, `tune_set`, 기본값 한 줄뿐).
  - RTL8831BU는 `8851bu` 드라이버라 경로 시험 대상도 아닙니다. 두 동글이 함께 안 되므로 동글이나 0.1.10보다 헤드유닛 쪽 상태(usbwifi.hotspot 데몬, HMG-API 설치 뒤 재부팅 전 상태 등)가 의심됩니다. 로그가 없어 확인하지 못했습니다.
- Mac의 BSD grep으로 11MB debug logcat을 `-v -i -E`로 거르는 데 0.28초. 거르기 자체가 수 분 걸릴 정도는 아닙니다. 사용자가 설정만 넣는 실행으로 알고 일찍 뺀 것으로 봅니다(완료를 알 수단이 없었음).

### trylog 9
- 단계 1에서 설정 파일을 먼저 적용하고 sync합니다(스틱을 일찍 빼도 설정은 들어감). 적용 전 장치의 설정(지난 시도에 쓰인 값)도 남깁니다.
- 단계마다 `[stage N done <시각>]`을 쓰고 sync합니다. 어디까지 저장됐는지 보입니다.
- 시작과 끝에 헤드유닛 토스트(`com.hkmc.intent.action.TOAST`): "EV6KR 로그 수집 중…", "EV6KR 로그 수집 완료: 스틱을 빼도 됩니다".
- 추가 수집: usbwifi.hotspot의 `config/hotspot.conf`(비밀번호·STA 값 가림), pid 파일별 데몬 생존과 대기 지점(`/proc/<pid>/wchan`), 디스크 대기(D 상태) 프로세스와 데몬의 자식 프로세스, USB 장치 목록(vendor:product, 제품명), `vm.dirty_*`, USB 마운트, dmesg의 `hung`/`blocked for`, usbwifi `ui.log`.
- 작은 로그(apsync, usbwifi 데몬·hostapd·dnsmasq, HMG-API, dmesg)를 먼저, 큰 로그(netsample, debug logcat, logcat)를 나중에 받습니다. 독립 구성 로그는 그 모드가 설치돼 있을 때만 받습니다(지난 수집은 남은 11MB를 매번 복사).
- mksh에서 `${x#*(}`는 확장 glob `*(...)`의 시작으로 읽혀 "no closing quote"가 납니다. 괄호는 `\(`로 씁니다.

### 다음
1. 동글(RTL8812BU)을 꽂은 채 헤드유닛을 재시작하고, iPhone의 Wi-Fi 목록에 `Kia_xxxx`가 보이는지 확인합니다.
2. 되든 안 되든 trylog 9로 수집합니다(토스트가 뜰 때까지, 약 1분).
3. 핫스팟이 돌아오면 RTL8831BU로 카플레이를 먼저 시험합니다. 다른 칩이므로 "동글 문제인가"에 가장 직접적인 답이 됩니다. 그다음 RTL8812BU로 `txpath=cycle`을 시험합니다.

## 26. 열네 번째 수집 (2026-11-08 23:32, 23:38): 핫스팟 복구, 경로 B 송신 불량

로컬 사본(일련번호 줄 제거, 비밀번호 가림)은 저장소 밖 `~/hmg-private/trylogs/2026-11-08_2332`, `..._2338`에 있습니다.

### 핫스팟이 안 떴던 19:34~19:41
- usbwifi.hotspot이 LTE로 **GitHub에서 스스로 업데이트**합니다(`AUTO_UPDATE=1`). 오늘만 v2.0.3(16:22), v2.0.4(19:37:39), v2.0.8(23:32:23)이었습니다.
- 19:35:29 usbwifi 서비스 정지 → 19:36:43 재시작(RTL8831BU, CD-ROM 모드 전환) → 19:37:30 AP가 2.4GHz ch6으로 한 번 바뀜 → apsync가 5GHz ch149로 되돌림(재시작 2회) → v2.0.4로 바뀐 데몬이 다시 시작.
- 그 뒤 19:41까지 AP가 20~40초마다 다시 만들어졌습니다. 데몬 로그에는 매번 `SoftAP active`가 찍혔지만, 휴대폰은 붙을 틈이 없었습니다.
- 재부팅 뒤(23:32:44)에는 RTL8812BU로 바로 떴습니다. 19:34 trylog 8은 일찍 빠졌는데도 `txpath=cycle`이 장치에 들어가 있었습니다(25절의 추정은 틀림). 언제 들어갔는지는 모릅니다.
- v2.0.8은 드라이버를 올릴 때 `rtw_country_code=KR`을 덧붙입니다. 다음 부팅부터 적용되는 우리가 바꾸지 않은 변수입니다.

### 송신 경로 시험 (RTL8812BU, 23:32~23:35, 9단계 중 5단계)
| 단계 | 경로 | ping 응답 | 수신 속도(5초) | 일 |
|---|---|---|---|---|
| 23:32:48~ | A | 2/8 | 1.4~2.5Mbit/s | 23:32:49 세션, 23:32:55 화면 |
| 23:33:09~ | B | 3/8 | 2.4 → 1.0 → 0.05 | 23:33:16 `screen stream timeout`(전환 7초 뒤) |
| 23:33:34~ | AB | 10/16 | 0.1 → 3.0 | 23:34:04 세션 끝(74초, -6753) |
| 23:34:00~ | A | **16/16** | 1.6 → **7.25** → 4.6 | 23:34:11 새 세션·화면 |
| 23:34:24~ | B | **0/16** | 4.6 → 0.14 | 23:34:38 세션 끝(26초, -6753) |

- 경로 B로 바꿀 때마다 링크가 무너졌습니다. 시험 자체가 이번 끊김 두 번을 만들었습니다.
- 수신 SNR은 경로 A/B가 비슷합니다(37/34, 37/38, 38/35dB). **체인 B는 받기는 정상이고 내보내기가 불량**입니다.
- 경로 A만으로는 최고 7.25Mbit/s, 응답 16/16이었습니다. "경로 A가 약하다"는 24절 가설은 틀렸습니다. 기본값(A)이 셋 중 가장 좋습니다.
- 드라이버는 1-stream 프레임은 A로만 보냅니다. 2-stream 데이터(MCS8~15)와 1-stream 2TX(STBC/CDD)에는 체인 B도 씁니다. 6·7·12차의 높은 재전송(58~89%)을 이것으로 설명할 수 있습니다.

### 다음 실험
- `txpath=driver`로 되돌림(재연결 때마다 경로 시험이 다시 돌기 때문).
- **1T2R**: v5.8.7.1 모듈 인자 `rtw_rf_path=1`(RF_1T2R: 송신 A, 수신 A+B). `rtw_hal_rfpath_init`이 IC 능력(2T2R)의 부분집합이면 받아들이고, `max_tx_cnt`·`tx_nss`가 1이 됩니다. usbwifi.hotspot은 `config/hotspot.conf`의 `MODULE_ARGS`로 드라이버를 올리고, 드라이버가 인자를 거부하면 기본 인자로 다시 올립니다(v2.0.8에서 확인). 다음 부팅부터 적용됩니다.
- RTL8831BU(1T1R 칩)로 같은 시험. 체인 B 문제를 하드웨어로 피합니다.

### trylog 10
- 이전 수집을 `EV6KR-TRYLOG.1`, `.2`…로 남깁니다(한 번에 여러 시도를 모아도 덮어쓰지 않음).
- `EV6KR-RFPATH.txt`(`1T2R` 또는 `default`): usbwifi `MODULE_ARGS`에서 `rtw_rf_path=`를 빼고 1T2R이면 `rtw_rf_path=1`을 붙입니다. 처음 바꿀 때 원본을 `hotspot.conf.ev6kr-orig`로 남깁니다. `default`는 원래 줄로 돌립니다(Mac 시험: 두 번 적용해도 한 번, 되돌리면 원본과 같음, 비밀번호의 `\`·`$` 보존).
- 요약에 `MODULE_ARGS`·`AUTO_UPDATE`, `/sys/module/88x2bu/parameters/`(rtw_rf_path, rtw_tx_nss, rtw_rx_nss, rtw_country_code), 마지막 드라이버 적재 줄을 남깁니다.
- 23:32 수집은 20초 만에 끝났습니다(단계 1→4).

## 27. 새 동글(RTL8851BU)이 CD-ROM에서 바뀌지 않음 (2026-11-08 23:50)

- 차(19:36, 19:40): 두 번 모두 `0bda:1a2b` "Realtek DISK"로 잡혔습니다. usb-storage가 붙고 SCSI INQUIRY에 `CD-ROM RTK Driver Storage 2.04`로 답했으며, 66초·73초 동안 리셋 없이 유지됐습니다. 이 커널은 `CONFIG_BLK_DEV_SR` 없이 `CONFIG_CHR_DEV_SG=y`라서 `sg0`만 생깁니다.
- 이런 Realtek "ZeroCD" 동글은 가상 CD를 꺼내야(SCSI START STOP UNIT, LoEj=1: usb_modeswitch `-K`/StandardEject, Linux `eject`) 무선랜 id로 다시 잡힙니다.
- usbwifi.hotspot(v2.0.8까지)의 `trigger_usb_modeswitch`는 usb-storage를 떼고 CD 인터페이스를 `rtl8851bu`에 bind합니다. USB 드라이버는 id 표에 없는 장치(`1a2b`)를 받지 않으므로 전환되지 않습니다. 그동안 데몬은 이전 동글이 남긴 `rtwlan0/1`에 AP를 띄우고 `SoftAP active`를 기록했습니다(실제 무선 없음).
- Mac(xHCI): `0bda:1a2b` "DISK"로 잡히고 macOS가 DVD 드라이브(type 5)로 붙였습니다. 하지만 bulk 전송이 응답하지 않아 macOS가 약 30초마다 리셋하다가 포기했습니다. libusb로 보낸 CBW(ALLOW MEDIUM REMOVAL, eject)도 bulk OUT 시간 초과였고(제어 전송·mass storage reset·clear halt는 성공), 포트 리셋 뒤에는 버스에서 사라졌습니다. Mac에서는 전환을 확인하지 못했습니다.
- 판단: USB 제어 경로는 살아 있고, 차(EHCI)에서는 bulk도 됐습니다. 결함 여부는 Windows/Linux PC에서 확인합니다(드라이버 설치 또는 `usb_modeswitch -KW -v 0bda -p 1a2b` 뒤 `lsusb`에 `0bda:b851`/`b831`이 보이는지).
- 차 쪽 해결안(미구현): apsync가 `0bda:1a2b`를 보면 usb-storage를 다시 붙이고, vendor `RTK`/model `Driver Storage`인 `sgN`을 찾아 sg 쓰기 인터페이스로 ALLOW MEDIUM REMOVAL과 START STOP UNIT eject를 보냅니다(36바이트 `sg_header` + 6바이트 CDB를 `dd`로 한 번에 씀). `/dev/sgN`은 ueventd가 만듭니다(확인 필요).

## 28. 1T2R 첫 시도 (2026-11-08 23:49~23:59): 1T2R이 적용되지 않았음

- 00:03 수집의 uptime은 1176초(23:43:40 부팅)였고, 드라이버 인자는 `rtw_rf_path=8`(RF_TYPE_MAX, 칩 기본 2T2R), `rtw_country_code=KR`(usbwifi v2.0.8이 덧붙임)이었습니다. 23:48 스틱이 `MODULE_ARGS`에 `rtw_rf_path=1`을 넣었지만 그 뒤로 재부팅이 없어서, 23:49~23:59 시험은 기존 2T2R로 돌았습니다.
- 23:50 세션: 화면 22초(1.0~1.9Mbit/s) 뒤 `screen stream timeout`, 세션 65초(-6753). 그 뒤 iPhone은 재접속만 반복했습니다. 23:59~00:03에는 새 동글(CD-ROM)이 다시 꽂혔습니다.
- 샘플러의 `rx_signal`에 송신 속도가 남습니다. 2T2R에서는 `MCS15`/`MCS10`/`MCS11`(2-stream, 체인 B 사용)이 자주 보였습니다. 1T2R이면 `MCS7` 이하여야 합니다.
- 이 드라이버 빌드는 커널 로그를 남기지 않습니다(`RTW:` 줄 없음). 실제 송신 체인은 BB 0x80c 하위 바이트로 알 수 있습니다(`(tx_path<<4)|tx_path`: 2T 0x33, A만 0x11). 다음 apsync에서 읽을 후보입니다.
- **trylog 11**: `rtw_rf_path`는 0644 모듈 인자이고, 드라이버는 동글이 꽂힐 때마다(probe의 `loadparam`) 이 값을 읽습니다. 그래서 `EV6KR-RFPATH.txt`가 `/sys/module/88x2bu/parameters/rtw_rf_path`에도 1(또는 `default`면 8)을 씁니다. 스틱 다음에 꽂는 동글부터 재부팅 없이 1T2R입니다. `MODULE_ARGS`는 이후 부팅용으로 그대로 둡니다.

## 29. 1T2R 시험 (2026-11-09 00:08~00:12): 적용됐지만 송신 손실은 남음

- 00:08:17 스틱이 `rtw_rf_path`를 1로 바꿨습니다(실행 중 인자). 00:08:53 기존 동글 AP. 00:10:32 재부팅. 직전 00:10:26~29에 HMG-API 앱 화면과 버튼음이 있고 크래시 흔적(pstore 등)은 없어서 사용자 재시작으로 봅니다. 새 부팅은 `MODULE_ARGS`의 `rtw_rf_path=1`로 드라이버를 올렸습니다.
- **1T2R 적용 확인**: 두 부팅 모두 송신 속도가 MCS4~5뿐이었습니다(2T2R 때의 MCS8~15 없음).
- 첫 부팅(실행 중 전환): 00:09:43 iPhone 접속, 00:09:47·00:09:58 pair-verify 중 연결 리셋(-6753). 세션은 만들어지지 않았습니다.
- 새 부팅: 00:11:35 세션, 00:11:38 화면, 00:12:14 화면 멈춤, 00:12:15 세션 끝(46초). `screen stream timeout` 없이 끝났고 00:12:20에 동글이 빠졌으므로, 끝은 동글을 뺀 것으로 보입니다.
  - 수신 속도(5초): 4.3 → 1.2 → 2.5 → 1.1 → 0.25 → 0.12Mbit/s. 화면은 끝나기 전에 이미 거의 멈춰 있었습니다.
  - ping 손실: 80~93%(00:11:36), 73~80%(00:12:12). 응답 중복이 최대 +8개 있었습니다. iPhone이 동글의 ACK를 못 받아 다시 보낸 흔적입니다.
  - iPhone은 접속 뒤 동글을 뺄 때까지 재접속하지 않았습니다(2T2R 때는 반복). 표본이 짧아 개선이라고 보기는 어렵습니다.
- 판단: 체인 B 송신은 사실상 죽어 있고, 체인 A만 써도 송신 손실이 큽니다. 수신은 두 체인 모두 강합니다(SNR 31~38dB). **동글 송신부(하드웨어) 또는 USB 전원**이 원인으로 남습니다. 소프트웨어 설정(block ack, 경로, 1T2R)으로는 고쳐지지 않았습니다.
- 다음: 다른 동글(RTL8851BU는 PC에서 정상 확인 후 차에서 CD 꺼내기 구현), 외부 전원 USB 허브, (소프트웨어로 싸게) 5GHz 36번 채널. 드라이버에는 `tx_power_offset` proc과 `rtw_target_tx_pwr_5g_a/b` 인자도 있지만 차에서 써 본 적이 없습니다.

## 30. apsync 0.1.11: ZeroCD 동글의 CD 꺼내기 (ipTIME AX900UA, RTL8831BU)

- 새 동글은 ipTIME AX900UA(RTL8831BU, Wi-Fi 6 + 블루투스)입니다. 이 커널에는 `CONFIG_BT_HCIBTUSB`가 없어서, 전환 뒤 블루투스 인터페이스는 아무 드라이버에도 붙지 않습니다(차 블루투스와 무관).
- `shared/rtwlan.sh` `zerocd_check`(tunewatch, 3초마다):
  - `ZEROCD_IDS`(기본 `0bda:1a2b`)인 USB 장치를 찾고, 인터페이스의 `host*/target*/H:C:T:L/scsi_generic/sgN` 가운데 SCSI vendor가 `RTK`인 것을 찾습니다(readlink 없이 경로로).
  - usb-storage가 떨어져 있으면 다시 bind하고 최대 `ZC_WAIT`(3)초 기다립니다(usbwifi.hotspot이 매번 unbind함).
  - `/dev/sgN`에 `dd bs=42 count=1`로 `bin/sg-allow.bin`(1e: ALLOW MEDIUM REMOVAL), `bin/sg-eject.bin`(1b … 02: START STOP UNIT, LoEj)을 씁니다. 파일은 32비트 ARM `struct sg_header` 36바이트(pack_len 42, reply_len 36, 나머지 0) + 6바이트 CDB입니다. sg v2 쓰기 경로는 input_size 0, reply 0이라 데이터 전송 없음(`SG_DXFER_NONE`)으로 명령만 보냅니다. dd는 장치 파일에 truncate하지 않습니다(`may_open`이 문자 장치의 O_TRUNC를 지움).
  - 꽂을 때마다(포트+devnum) 최대 `ZC_MAX`(4)번. 같은 포트에 다른 id가 나타나면 `USB device at 4-1 after the CD: <vid:pid> (<product>)`를 남깁니다.
  - 로그: `dongle CD-ROM … eject sent through sgN`, `no SCSI device`, `no /dev/sgN node`, `still a CD after 4 tries`.
- 드라이버 `/proc` 접근(샘플러, 튜닝, 송신 경로)은 `RTL_PROC_DIR=rtl88x2bu`로 한정했습니다. 8851bu 드라이버의 `/proc` 항목은 차에서 읽어 본 적이 없습니다(`drv_cfg` 교훈).
- 확인할 것: `/dev/sgN`이 ueventd로 생기는지(trylog 12가 스틱 자신의 sg로 확인), 전환 뒤 id(`0bda:b831`이면 usbwifi와 8851bu 드라이버 표에 있음. ipTIME 고유 id면 `new_id` 추가 필요).
- 테스트: apsync 58개(ZeroCD 5개, 8851bu `/proc` 1개 추가), 독립 구성 통과(sh, dash, mksh). 차량 미시험.
- trylog 12: `/dev/sg*` 목록, `/sys/class/scsi_generic/*/device/{vendor,model}`, apsync 로그의 CD 줄.

## 31. 열다섯 번째 수집 (apsync 0.1.11 + ipTIME AX900UA, 2026-11-09 00:35~00:37): 처음으로 깨끗한 세션

- 00:34:56 apsync 0.1.11 시작. 00:35:14 `dongle CD-ROM 0bda:1a2b at 4-1` → `eject sent through sg0 (try 1 of 4)`. 00:35:18 `USB device at 4-1 after the CD: 0bda:b831 (802.11ax WLAN Adapter)`. sg 쓰기 방식의 꺼내기가 첫 시도에 됐고, `/dev/sg0`도 ueventd가 만들었습니다.
- 00:35:31 usbwifi가 8851bu의 `rtwlan2`에 AP를 띄움, 00:35:34 `AP-ENABLED`(CD 꺼내기부터 20초).
- 00:35:48 iPhone 접속 → 00:35:49 pair-verify 1·2가 10ms 안에 끝나고 세션 시작(이전 동글은 수 초 걸리거나 리셋), 00:35:50 화면.
- 00:35:58 화면 재시작 1번(timeout 아님) 뒤 **00:35:59~00:37:02 63초 동안 끊김 없음**. 00:37:05 동글을 뽑아 끝남(세션 76초). 재접속 0번, `screen stream timeout` 0번.
- 수신 속도(5초 평균): 1.2, 0.3, **17.7**, 3.2, 3.3, 8.8, 0.9, 4.5, 9.7, 1.5, 3.6, 1.5Mbit/s. 송신 오류·드롭 0.
- iPhone ping: **0% 손실**(5/5, 56·1400바이트, 두 번). RTL8812BU에서는 같은 거리에서 50~93%였습니다. 다른 Apple 기기(.10)의 손실은 절전 응답 없음으로 봅니다.
- 결론: 끊김의 원인은 **RTL8812BU 동글의 송신 하드웨어**였습니다. 소프트웨어 구성(usbwifi.hotspot + apsync 0.1.11 + 모드 0.1.8)은 정상 동작합니다.
- 정리: 스틱의 `EV6KR-RFPATH.txt`를 `default`로 바꿨습니다(다음 스틱 실행 때 usbwifi `MODULE_ARGS`에서 `rtw_rf_path=1`을 빼고 실행 중 인자도 8로 돌림. 88x2bu에만 해당).
- 다음: 10~15분 이상 실제 주행(지도·음악·통화), 시동을 껐다 켠 뒤 자동 연결(부팅 때 CD 꺼내기 → AP → 카플레이까지 걸리는 시간).

## 32. apsync 0.1.12: 차 LTE 공유 끄기 (순정 동작)

- usbwifi.hotspot의 `ENABLE_LTE_NAT=1`(기본)은 `ip_forward=1`, `192.168.43.0/24 → rmnet+` MASQUERADE, DHCP 게이트웨이(option 3)와 통신사 DNS(option 6)를 줍니다. iPhone은 이 Wi-Fi를 인터넷 연결로 보고 자기 트래픽을 차 모뎀으로 보냅니다. 00:37 부팅은 `Forwarding=1`, `ForwDatagrams=6258`이었습니다.
- 순정 카플레이 핫스팟은 인터넷을 주지 않습니다. iPhone은 Wi-Fi를 카플레이에만 쓰고 데이터는 셀룰러로 보냅니다.
- 0.1.12: `ENABLE_LTE_NAT`를 관리 키에 넣고 항상 0으로 씁니다(30초마다, 대시보드나 OTA가 바꿔도 되돌림). 바뀌면 usbwifi를 재시작합니다. 재시작하면 데몬이 기록해 둔 NAT·DNAT 규칙을 지우고, dnsmasq를 게이트웨이 없이(`--dhcp-option=3`) 다시 띄웁니다. 로그: `car LTE sharing on the USB hotspot off (ENABLE_LTE_NAT 1 -> 0)`.
- 백업: 0.1.11에서 올라온 차는 백업에 이 키가 없습니다. 처음 바꾸기 전 값을 한 번만 덧붙입니다(`saved the USB hotspot's own ENABLE_LTE_NAT for uninstall`). 제거할 때 원래 값(1)으로 돌립니다.
- 설정 파일 `lte_share=1`이면 다시 공유합니다(기본 0).
- usbwifi는 NAT를 꺼도 DNS DNAT(192.168.43.1:53 → 통신사 DNS)를 남깁니다. MASQUERADE가 없어서 밖으로 나가지 못하고, 게이트웨이가 없으니 iPhone도 인터넷 용도로 쓰지 않습니다.
- 테스트: apsync 62개(LTE 4개 추가), 독립 구성 통과(sh, dash, mksh). trylog 13은 `ENABLE_LTE_NAT` 줄도 남깁니다(스틱에 복사함).

## 33. 카플레이 모드 0.1.9: ★ 키에 "Apple CarPlay"

- `mod/mod.json`에 `provides.star_key` 한 항목: `{"id": "carplay", "title": "Apple CarPlay", "broadcast": "com.hkmc.intent.action.DIPO_CUSTOM_SHORTCUT"}`. HMG-API가 ★ 목록 두 화면(`CustomButtonSetting` 헤드유닛·내비 ★, `CustomButtonSettingSWRC` 운전대 ★)에 선택지로 넣고, 저장값은 `hmgapi.star.wireless-carplay-kr.carplay`입니다. ★를 누르면 `StarKey.run`이 이 broadcast를 보냅니다.
- 순서: HMG-API 자신의 "Open HMG-API" 다음에 모드 항목이 모드 폴더 이름 순(`Arrays.sort`)으로 붙습니다. 이 차는 `nemesis-shortcut`("Open NEMESIS") 다음이 `wireless-carplay-kr`이라 세 번째입니다. id가 앞서는 모드를 더 설치하면 밀립니다.
- 국내형 순정 DiPO(`HKMC_DiPO.odex`, md5 caf67d3b…)는 `DipoService`에서 이 액션을 권한 없이 `registerReceiver`하고, `w.onReceive`가 처리합니다.
  - 비상 모드이거나 `isDipoActivated()`가 아니거나 `mCarPlayUtils`가 없으면: 무시
  - 카플레이가 연결돼 있으면: 화면을 켜고 카플레이 화면으로 전환(메시지 0x46)
  - 그 밖의 경우: DiPO의 다른 분기(차량 확인 필요)
- 이 차의 on-car 맵에 ButtonSettings 31개 지점이 모두 있고, ★ 목록에는 이미 모드 항목 2개가 나옵니다.
- 번들 이름에 모드 버전을 넣었습니다: `ev6kr-wireless-carplay-<apsync>-mod<mod>-nemesis.zip`. 같은 apsync에 새 모드를 넣으면 기존 파일을 바꾸지 않고 새 파일이 생깁니다(0.1.12 번들은 그대로).
- 설치 뒤 헤드유닛 재시작 필요(모드는 부팅 때 zygote가 읽음). 차량 미시험.

## 34. 카플레이 길안내(TBT): T맵은 되고 네이버지도는 안 됨, 모드 0.1.10 진단 로그

- 차량 확인(2026-11-09): 같은 구성(apsync 0.1.12 + 모드 0.1.9)에서 **T맵은 계기판·HUD에 길안내가 나오고, 네이버지도는 나오지 않습니다**. 그래서 모드의 TBT 경로는 동작합니다(iAP2 서버가 RouteGuidance를 iPhone에 알림 → DiPO가 시작 요청 → HMG-API 리스너 → CpTurns → NavigationCluster).
- 00:35~00:37 수집(앱 미확인)에서 확인한 것:
  - iAP2 서버가 식별 정보에 `RouteGuidanceComponent0`를 넣음(블루투스 세션 4, 카플레이 채널 세션 5 모두): `Route... GetComponet mName RouteGuidanceComponent0`
  - DiPO 프로세스에 `Iap2SvcInit(HMGAPI_RG, 0x1000) = true`
  - iPhone이 길안내를 잡자(`turns controller`, 00:36:19) DiPO가 `Iap2SvcStartRouteGuidanceUpdate`를 부르고, 30바이트가 카플레이 채널로 나감
  - 그 뒤 47초 동안 DiPO 프로세스에서 NavigationCluster 호출이 없었고, iPhone에서 들어오는 iAP 메시지 수도 늘지 않음(초당 1~3개, 길안내 전과 같음). 그때 쓴 앱이 길안내 정보를 보내지 않은 것으로 보입니다.
  - `iAP2UsedRouteGuidance[0]` 줄은 `checkSupportsFeatures` 안에서 찍히고, 모드는 그 뒤(after 훅)에 1로 바꿉니다. 이 줄은 문제가 아닙니다.
- iPhone은 RouteGuidanceUpdate에 앱 이름(SourceName, 항목 19)과 "이 앱이 계기판 길안내를 지원하는지"(SourceSupportsRouteGuidance, 항목 20)를 넣습니다. 서드파티 앱은 앱이 CarPlay 길안내 메타데이터를 직접 제공해야 차 계기판에 나옵니다. 네이버지도가 이를 제공하지 않으면 모드에서 고칠 수 있는 부분이 없습니다.
- 모드 0.1.10(진단): CpTurns·Dipo·Wireless에 로그만 추가했습니다(동작 변경 없음).
  - `iAP2: route guidance offered to the phone (stepofspec 110)`: iAP2 서버 프로세스당 한 번
  - `CarPlay: route guidance update #N: …`, `maneuver #N: …`, `lane guidance #N: …`: 처음 5/8/3개, 그 뒤 100개마다. 항목별 `id=iAP2형:값`이고, 도로·장소 이름은 글자 수만, 앱 이름과 거리 문자열(항목 8, 11, 19 / 기동 항목 6)은 그대로 남깁니다.
  - `CarPlay: turn-by-turn …`: `turn()`의 결과를 세션마다 종류별로 한 번씩 남깁니다. 경로 없음(state 0, 앱 이름, 지원 여부), 기동 정보 없음, 현재 기동 목록 없음, 기동 N을 아직 못 받음, 계기판 아이콘이 없는 기동 종류, `to the cluster: icon …`.
  - `CarPlay: DiPO stops the phone's route guidance`, `CarPlay: route guidance session ended: N updates, …`
- 다음 시험: 0.1.10 설치 → 재시작 → T맵과 네이버지도로 각각 1~2분 길안내 → TRY_LOG 수집. 네이버지도에서 `route guidance update`가 아예 없거나 `supports route guidance false`이면 앱 쪽 문제입니다. 기동은 오는데 `no cluster icon`이나 `not received`이면 CpTurns를 고칠 수 있습니다.

## 35. 열여섯 번째 수집 (2026-11-09 00:54, 08:11, 08:17): 24분 주행, 길안내 진단, 모드 0.1.11

- 복사본: `~/hmg-private/trylogs/2026-11-09_005445`, `_081134`, `_081731`, `_081746` (시리얼 줄 제거, 비밀번호 가림).
- **24분 주행 (08:11 수집, apsync 0.1.12 + 모드 0.1.9, 부팅 07:46:18):**
  - 07:46:32 CD 꺼내기(sg0, 첫 시도) → 07:46:35 `0bda:b831`
  - 07:47:07 카플레이 세션 시작(부팅 49초 뒤)
  - 08:11:24 종료(`cpClient=false`, 수집하려고 뺀 것). 그 사이 세션이 끊긴 기록 없음
  - 이 부팅은 debug logcat·netsample이 돌지 않아 핑·처리량 기록은 없습니다.
  - ★ 키: 07:47:10, 07:50:03에 `star key: carplay`(HMG-API가 broadcast 보냄). DiPO가 화면을 바꿨는지는 logcat이 없어 로그로는 확인 못 했습니다.
- **길안내 진단 (08:17 수집, 모드 0.1.10, 부팅 08:13:42):**
  - `iAP2: route guidance offered to the phone (stepofspec 110)`, `Iap2SvcInit(HMGAPI_RG, 0x1000) = true`
  - 08:14:45~08:15:24 **T맵**: `turns controller` → DiPO `Iap2SvcStartRouteGuidanceUpdate` → 0.02초 안에 RouteGuidanceUpdate(구성요소 5, `19='TMAP'`, `20=[1]` 지원함)와 기동 6개(종류 3, 50) → `to the cluster: icon 65 for maneuver type 3`. 차선 정보는 보내지 않음.
  - 08:15:56~08:17:16 **두 번째 앱(네이버지도로 보임)**: DiPO가 같은 시작 요청을 보냈지만 기동 0개, 앱 이름 변경 로그도 없음. iPhone에서 들어온 iAP 메시지는 초당 2.0개로 길안내가 없을 때(2.1개)와 같고, T맵 때는 3.7개였습니다. **네이버지도는 CarPlay 길안내 정보를 보내지 않습니다.** 차 쪽에서 고칠 수 없습니다.
  - 세션 합계: 업데이트 92, 기동 6, 차선 0.
- **T맵 데이터에서 찾은 빈칸:** T맵 기동에는 진출 각도(항목 10, 11)가 없고, 교차로 종류와 주행 방향이 0입니다. CpTurns(원본 그대로)는 급회전·약간회전(47~50)을 정확한 각도가 있을 때만 아이콘으로 바꿨습니다. 그래서 T맵이 "약간 오른쪽"(50)을 보내면 계기판이 비었습니다. keep left/right(13/14), 출구(8), 도로 끝 좌·우회전(20/21), 가능할 때 유턴(26), 경로 끝 도착(10/27)은 아예 매핑이 없었습니다.
- **모드 0.1.11:** `CpTurns.icon`과 `aheadIcon`을 보강했습니다. 번호는 이 모드에서 이미 쓰는 것만 씁니다(AaTurns: 약간 66/71, 급 68/69, 분기 173/174, 출구 86, 회전 67/70, 유턴 72/73, 도착 112/3).
  - 각도 없음(0): 47→69, 48→68, 49→71, 50→66
  - 13→174, 14→173, 8→86, 20→70, 21→67, 26→72/73, 10·27→112(도착하면 3)
  - 각도가 있으면 기존 매핑 그대로. 컴파일된 클래스로 확인했습니다(T맵 형태 21종, 각도 있는 경우 5개).
  - 회전교차로(6, 28~35)와 고속도로 변경(51)은 그대로 비어 있습니다. 쓰이면 0.1.10의 `has no cluster icon` 로그에 남습니다.
  - 차량 미시험. 번들: `dist/ev6kr-wireless-carplay-0.1.12-mod0.1.11-nemesis.zip`.

## 36. 네이버지도: 앱 설정의 HUD 스위치

- 차량 확인: T맵은 계기판과 HUD 모두 정상입니다.
- 커뮤니티 후기(2024-07 업데이트 이후): 네이버지도는 카플레이 HUD 길안내를 지원하지만, **네이버지도 카플레이 설정(톱니바퀴 → 네비게이션 탭)의 HUD 스위치를 켜야** 보냅니다. 공식 문서는 찾지 못했습니다.
- 35절의 두 번째 구간과 맞습니다. 네이버지도는 "지원 안 함"이나 "경로 없음" 같은 RouteGuidanceUpdate도 보내지 않았고, 앱 이름도 오지 않았습니다. iPhone은 길안내를 시작했지만 앱이 메타데이터를 넘기지 않은 상태입니다.
- 다음: 스위치를 켜고 다시 시험합니다. 모드 0.1.10 이상의 진단 로그에 네이버지도 이름(SourceName)과 기동이 나오는지 봅니다. 켜도 아무것도 오지 않으면, 앱이 차의 식별 정보(RouteGuidanceDisplayComponent의 길이 제한·기동 저장 수, 차선 지원 여부 등)를 보고 거르는지 살펴볼 차례입니다.
- 사용자 확인(2026-11-09): 네이버지도의 HUD 스위치가 꺼져 있었고, 켰습니다. 켠 뒤 차량 시험 결과는 아직 없습니다.

## 37. 시동 후 카플레이 연결 시간, 모드 0.1.12: DiPO를 블루투스 준비 시점에 시작

- 사용자 관찰(2026-11-09): 연결은 매끄럽지만 실제 카플레이로 넘어가기까지 약 10초가 걸립니다.
- **부팅 08:13:42의 시간표**(35절 08:17 수집, 부팅 뒤 초. debug logcat과 HMG-API 로그):

  | 초 | 일 |
  |---|---|
  | 14 | 동글 인터페이스 `rtwlan0/1` 생성 |
  | 21 / 24 | hostapd `AP-ENABLED` / DHCP 준비(`SoftAP active`) |
  | 19 | Broadcom BT 관리자(BTCM) 시작 |
  | 30 | `BTCM_INIT_COMPLETED` |
  | 34 | BTCM 자동 연결 시작 |
  | 37 | iPhone SPP 연결 |
  | 39 | iPhone이 동글 AP에 자동 접속, DHCP |
  | 41 / 43 | HFP 연결 / 블루투스 연결 완료 |
  | **47** | DiPO가 `BOOT_COMPLETED`를 받아 `DipoService` 시작(DiPO 프로세스는 10초부터 떠 있음) |
  | 48 | 카플레이 라이브러리 로드, 브리지가 SPP 확인, iAP2(블루투스) 시작 |
  | 50 | MFi 인증 성공(1.5초), Wi-Fi 정보 전송 |
  | 51 | `TccCarPlay_Start`, Bonjour로 iPhone 발견(0.2초), pair-verify |
  | 51.5 / 52 | 세션 생성 / 화면 스트림 시작, `DipoActivity` |

- **낭비 구간은 하나입니다.** SPP는 37초에 붙고 iPhone도 39초에 AP에 붙었는데, DiPO 서비스가 47초에야 떠서 11초를 기다렸습니다. 서비스가 뜬 뒤 화면까지는 4~5초이고, 그 대부분은 iAP2 인증(MFi 칩)이라 줄일 여지가 거의 없습니다.
- 다른 부팅도 같은 꼴입니다(같은 스크립트로 계산):

  | 부팅 | BTCM 준비 | SPP 연결 | 폰 AP 접속 | DiPO 시작 | 세션 |
  |---|---|---|---|---|---|
  | 11-09 00:38 | 40 | 44 | 30 | 46 | 53 |
  | 11-09 00:50 | 40 | 46 | 26 | 46 | 52 |
  | 11-09 08:13 | 30 | 38 | 40 | 48 | 52 |

  BT 스택 준비는 부팅마다 30~40초로 흔들립니다. DiPO 시작은 늘 46~48초입니다.
- **원인:** DiPO(`DipoReceiver`, 매니페스트 수신기)는 `BOOT_COMPLETED`에서 `DipoService`를 시작합니다. 매니페스트 수신기 방송은 한 줄로 차례대로 배달되는데, 이 차에서 `BOOT_COMPLETED`는 19초쯤 나가 47초쯤 DiPO 차례가 옵니다. DiPO 수신기는 `com.broadcom.bt.hfdevice.hfbtcm.action.BTCM_INIT_COMPLETED`도 받습니다. 서비스가 아직 없으면 그때도 `startService`를 부르게(`DipoService is not running. skip intent` 분기) 짜여 있습니다. 하지만 이 방송도 같은 줄 뒤에 서므로 실제로는 늘 `BOOT_COMPLETED`가 먼저 닿습니다. 동적으로 등록한 수신기(GPM, 내비)는 바로 받습니다.
  - 같은 방송의 도착 시각(GPM → DiPO): 00:38:45.9 → 00:39:02.7, 00:50:55.5 → 00:51:12.7, 08:14:12.6 → 08:14:42.0. DiPO는 17~30초 늦게 받습니다.
- `DipoService.onStartCommand`는 action 없는 인텐트면 로그만 남기고 `START_STICKY`를 돌려줍니다. 서비스를 미리 시작해 두면 나중의 순정 시작은 아무것도 바꾸지 않습니다.
- **모드 0.1.12:** DiPO 앱 부분이 `BTCM_INIT_COMPLETED`용 수신기를 등록합니다(DiPO 프로세스는 10초에 뜨므로 놓치지 않음). 받으면 부팅 3분 안이고 `DipoService`가 아직 없을 때 DiPO 수신기와 같은 인텐트로 서비스를 시작합니다. 한 번 받으면 해제합니다.
  - 설정 `early_start`(기본 켬, 적용은 재시작)로 끌 수 있습니다.
  - 로그: `bridge: Bluetooth ready N s after power-on, DiPO's service started now, not at boot completed` 또는 `... already running`.
  - 예상: 세션이 SPP 연결 뒤 4~5초에 생깁니다. 08:13 부팅이라면 52초 → 42초쯤이고, BT가 늦은 부팅(00:38, 00:50)은 2~5초 당겨집니다.
  - 차량 미시험. 번들: `dist/ev6kr-wireless-carplay-0.1.12-mod0.1.12-nemesis.zip`. 0.1.11의 길안내 아이콘 보강이 포함되어 있습니다.
- **더 줄이려면(시험 안 함):** iPhone은 BT보다 먼저(26~40초) AP에 붙는 일이 많습니다. iAP2(블루투스) 없이 Bonjour만으로 세션을 시작하면 BT를 기다리지 않아도 됩니다. 하지만 DiPO의 흐름(`onTransportIdentifier` → `createDipo` → `startDipo`)이 iAP2 식별에 묶여 있어 손이 많이 가고 위험합니다. BT 자동 연결 시점(BTCM 준비 뒤 3~4초)은 Broadcom 스택 몫이라 건드리지 않습니다.

## 38. 순정 Wi-Fi 칩 유무 다시 확인 (2026-11-09): 켜지 않아서가 아니라 모듈이 없음

- 계기: Korea Projection(StopDragon/korea-projection, AGPL-3.0)은 "국내형 펌웨어에는 일반 Wi-Fi를 켜는 메뉴가 없어서, Wi-Fi를 한 번도 켜지 않은 차는 칩이 SDIO에 나타나지 않는다"고 보고 `svc wifi enable`로 한 번 켜서 칩을 깨웁니다(그랜저 #7 등). 이 말대로라면 우리 근거였던 "`/sys/bus/sdio/devices` 비어 있음"만으로는 칩이 없다고 단정할 수 없습니다.
- 그 설명 자체는 Broadcom SDIO 모듈에서 맞습니다. 모듈 전원(WL_REG_ON)은 `bcmdhd.ko`를 올릴 때 켜지므로, 드라이버를 올린 적이 없으면 칩이 있어도 SDIO 장치가 없습니다.
- 하지만 이 차에는 SDIO와 무관한 하드웨어 근거가 있습니다.
  - 순정 `libhardware_legacy.so`의 `wifi_get_module_version()`은 `bsp_version_get_bt_version()`을 부릅니다. 이 함수는 `/dev/daudio_info`에 ioctl `0x6964`를 보내 보드의 BT/Wi-Fi 모듈 버전을 받습니다(값 + 1). 드라이버 로드와 상관없이 부팅 때 바로 정해집니다. 버전 5면 `bcmdhd5.cal`, 그 밖이면 `bcmdhd.cal`을 씁니다.
  - 순정 `WifiService.checkAndStartWifi()`는 `com.hkmc.software.wifi.module` 기능이 있어도 **모듈 버전이 3이면 `mWifiHWSupported=false`**로 바꿉니다. 제조사 코드가 버전 3을 "Wi-Fi 하드웨어 없음"으로 처리한다는 뜻입니다.
  - 이 차의 수집 9건(11-08 23:32 ~ 11-09 08:17) 모두 부팅 때 `I/WifiService: [Feature] Hardware(not supported), HW Variant(3), Client(not supported), Hotspot(not supported), Wireless(supported)`를 남겼습니다.
  - Korea Projection의 코드 주석도 같은 신호를 "부품 없음"으로 봅니다(#50: insmod 8초, 버전 3).
  - 부팅 커널 로그에서 SDIO 컨트롤러 `mmc1`(`16460000.sdhc`)이 0.46~0.71초에 카드 초기화를 네 번 시도하고(`Switching to 3.3V signalling voltage failed`), SDIO 카드 발견 줄은 없습니다(보조 근거).
- 판단: 국내형 차 중 모듈이 실제로 있는 차(그랜저, 쏘나타, 니로 등)에는 Korea Projection의 설명이 맞습니다. **이 EV6는 보드 자체가 모듈 버전 3(모듈 없음)을 알려 주므로, Wi-Fi를 켜도 `wlan0`은 생기지 않을 것으로 봅니다.** USB 동글 방식이 맞습니다.
- 확인하려면(하지 않음): `svc wifi enable`이나 `insmod /system/wifi/bcmdhd.ko`를 한 번 해 보고 SDIO 카드와 `wlan0`이 생기는지 봅니다. Korea Projection에 따르면 Wi-Fi를 켜면 USB와 블루투스가 다시 시작되므로, 동글 핫스팟이 잠시 끊길 수 있습니다.
- Korea Projection의 EV6 이슈(#63, 시험 중)는 Wi-Fi 단계까지 가지 못했습니다. 우리 첫 차량 시험(11절)과 같은 `btsettings.projection_helper` 매핑 문제로 무선 모드 훅이 통째로 꺼졌고, 1.7.2에서 그 지점을 빼는 중이라고 합니다.
