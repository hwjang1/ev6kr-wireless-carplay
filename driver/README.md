# USB Wi-Fi 동글 드라이버 (RTL8812BU / RTL8822BU)

`usb-hotspot-kr` 모드가 쓰는 드라이버입니다. 이 폴더의 파일은 **GPL-2.0**입니다(Realtek 드라이버의 수정분이기 때문). 저장소의 나머지는 AGPL-3.0입니다.

- 원본: [morrownr/88x2bu-20210702](https://github.com/morrownr/88x2bu-20210702) @ `418d71cc` (Realtek v5.13.1)
- 대상: 헤드유닛 커널 `3.18.24-tcc` (`vermagic 3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8`), AOSP `arm-eabi-4.7`
- 수정: [patch-88x2bu.py](patch-88x2bu.py). usbwifi.hotspot(HKG_5W_USB_Wlan)의 코드는 쓰지 않고 새로 작성했습니다.

## 빌드

```sh
driver/build.sh <차량 커널 설정> [tcc803x|tcc897x]
```

- **커널 설정**은 차량의 `/proc/config.gz`입니다. trylog 스틱(4판부터)이 `EV6KR-TRYLOG/kernel-config.gz`로 저장하며, `.gz` 그대로 넘겨도 됩니다.
- Docker(linux/amd64)가 필요합니다.
- 툴체인(AOSP kitkat-release `arm-eabi-4.7`), 커널 소스(kernel.org 3.18.24), 드라이버 소스는 처음 한 번만 받아서 `ev6kr-kbuild` 볼륨에 보관합니다.
  - 이미 받아 둔 볼륨이 있으면 `KBUILD_SEED_VOLUME=<볼륨>`으로 복사해 씁니다. 그 볼륨에 `arm-eabi-4.7/`과 `src/linux-3.18.24/`가 있어야 합니다.
- 결과물은 `build/driver/`에 생깁니다.
  - `88x2bu_<platform>.ko`
  - `.ids`: 이 드라이버가 받는 USB vendor:product. 서비스는 이 목록에 있는 동글이 꽂혔을 때만 드라이버를 올립니다.
  - `.srcversion`: 같은 이름의 다른 드라이버(usbwifi.hotspot의 것)와 구별할 때 씁니다.
  - `.info`: vermagic, sha256
- `tools/build.sh hotspot`이 이 결과물을 모드에 넣습니다.

## 수정 내용 (patch-88x2bu.py)

1. **usbfs가 동글을 열지 못하게 함.** 헤드유닛의 프로젝션 스택은 모든 USB 장치를 열어 Android 액세서리(AOA) 모드를 요청합니다. 드라이버가 동글을 잡고 있는 동안에는 장치 번호에 표시 비트(`0x00080000`)를 더합니다. 그러면 `/dev/bus/usb` 노드와 맞지 않아 `usbdev_open()`이 장치를 찾지 못합니다. 동글을 뺄 때와 probe가 실패할 때는 원래대로 돌립니다.
2. **뽑힌 동글은 해제 전에 "사라짐"으로 표시.** 원본은 넷디바이스를 먼저 해제하고 나중에 표시합니다. 그래서 해제 과정(hostapd의 stop_ap 등)이 이미 없는 장치에 USB 입출력을 시도합니다.
3. **ethtool 드라이버 정보의 NULL 가드.** v5.13.1에 새로 생긴 함수가 부모 장치를 그대로 따라갑니다. Android netd가 보내는 `ETHTOOL_GDRVINFO`에서 패닉이 날 수 있는 경로를 막았습니다.
4. **빌드 옵션.** `/proc` 진단 항목을 켭니다(샘플러와 송신 경로·전력 조정에 필요). PHY 파라미터는 내장하고, 송신 전력은 efuse의 속도별 값을 쓰며, 오류·경고는 dmesg에 남깁니다.
5. **RX A-MPDU 처음부터 거부.** iPhone의 block ack 세션을 받으면 이 드라이버가 카플레이 트래픽 시작 몇 초 만에 헤드유닛을 재부팅시켰습니다(8차 시험). `/proc/net/rtl88x2bu/<if>/rx_ampdu`에 255를 쓰면 실험용으로 다시 켤 수 있습니다.

인터페이스 이름(`rtwlan%d`), 절전 끄기, NAPI/GRO 끄기는 패치하지 않고 모듈 인자로 넘깁니다.

### usbwifi.hotspot 빌드와 다른 점 (차량 시험 전)
- **넷디바이스를 정상적으로 등록하고 해제합니다.** usbwifi.hotspot은 핫언플러그 때문에 부모 장치 연결을 빼고 해제하지 않았습니다(재연결 때 `rtwlan1`, `rtwlan2`… 로 늘어나던 원인). 이 빌드에서는 다시 꽂아도 `rtwlan0`으로 돌아옵니다. 8차 시험에서 동글을 뺄 때 커널은 버텼습니다(동글이 시작되지 않은 상태였음). 핫스팟이 떠 있을 때 빼는 경우는 아직 확인하지 못했습니다. 패닉이 나도 재부팅 뒤에는 동글이 없으면 드라이버가 잡을 장치가 없으므로 그대로 복구됩니다.
- **DHCP 67↔1067 포트 변환이 없습니다.** dnsmasq가 67번 포트를 그대로 씁니다.
