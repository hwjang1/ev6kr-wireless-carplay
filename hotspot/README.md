# usb-hotspot-kr: USB Wi-Fi 핫스팟 (독립 구성)

국내형 EV6(Wi-Fi 칩 없음)에서 무선 카플레이가 접속할 핫스팟을 USB Wi-Fi 동글로 띄우는 HMG-API 모드입니다. **usbwifi.hotspot과 ev6kr.usbap.sync가 필요 없습니다.**

| | usbwifi.hotspot + ev6kr.usbap.sync (기존) | usb-hotspot-kr (독립) |
|---|---|---|
| 드라이버 | usbwifi.hotspot의 빌드 | 이 저장소의 빌드 ([driver/](../driver/)) |
| SSID·비밀번호 | apsync가 usbwifi.hotspot 설정 파일을 고치고 재시작시킴 | `softap.conf`에서 바로 hostapd로 |
| DHCP | dnsmasq를 1067번 포트로 띄우고 드라이버가 변환 | dnsmasq를 67번 포트로 (게이트웨이·DNS 없음: iPhone은 자기 모바일 데이터를 계속 씀) |
| 인터넷 공유(LTE NAT) | 켜짐 | 없음 (카플레이에 불필요) |
| 자동 업데이트 | GitHub에서 스스로 업데이트 | 없음 |
| 진단·튜닝 | apsync | 같은 코드([shared/rtwlan.sh](../shared/rtwlan.sh)) |

## 동작
- HMG-API가 부팅할 때 root 서비스 `usbap`을 띄우고 감시합니다. 서비스는 시작하자마자 드라이버를 올립니다. 동글이 나타나는 순간 드라이버가 잡아야, 헤드유닛의 프로젝션 스택이 AOA 요청으로 동글을 건드리기 전에 막을 수 있습니다(늦게 올리면 `Chip id is undefined`로 동글이 시작되지 않음).
- 3초마다 다음을 확인합니다.
  1. usbwifi.hotspot이 설치돼 있으면 아무것도 하지 않습니다(같은 동글을 두고 다투지 않도록).
  2. 지원하는 동글(`modules/88x2bu_<platform>.ids`)이 꽂혀 있으면 드라이버를 올립니다. 인자: `rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0 rtw_en_napi=0 rtw_en_gro=0 ifname=rtwlan%d`
     - 이미 다른 `88x2bu`가 올라와 있으면(srcversion이 다르면) 그대로 두고 재부팅을 안내합니다.
     - 드라이버가 올라가지 않으면 그 부팅에서는 다시 시도하지 않습니다.
     - 동글이 꽂혔는데 드라이버가 잡지 못하면 약 12초 뒤 한 번 다시 붙이고, 그래도 안 되면 "동글을 다시 꽂으라"고 로그에 남깁니다.
  3. 순정 카플레이 핫스팟 설정(`/data/misc/wifi/softap.conf`의 ConnectivitySSID/PSK, 채널)을 읽어 hostapd를 띄웁니다(`/data/local/tmp/ev6kr_usbap/hostapd.conf`, root만 읽기 가능).
     - 주소는 `rtwlan0`에 `192.168.43.1/24`이고, Android 정책 라우팅 테이블(`ip rule`의 60, 61 등)에도 이 서브넷 경로를 넣습니다.
  4. dnsmasq로 DHCP를 띄웁니다(`192.168.43.10-100`).
  5. 동글을 빼면 hostapd와 dnsmasq를 끕니다. 다시 꽂거나, hostapd가 죽거나, 설정·채널이 바뀌면 다시 띄웁니다.
- iPhone의 A-MPDU(block ack)는 받지 않습니다. 드라이버가 처음부터 거부하고, hostapd를 띄우기 전에도 한 번 더 적용합니다. 받으면 v5.13.1 드라이버가 헤드유닛을 재부팅시켰습니다(8차 시험).
- 진단·튜닝은 apsync와 같습니다: 수신 backlog, netsample, 디버그 logcat, 송신 경로 순환 비교(`txpath=cycle`, 기본은 꺼짐), 송신 전력(`txpower`), 채널(`channel`).
- HMG-API 부팅 보호 장치가 훅을 꺼 두었으면(빠른 재부팅이 3번 이어진 뒤) 로그에 남깁니다. trylog 스틱에 `EV6KR-HOOKS-RESET`을 두고 실행하면 초기화됩니다.
  - ev6kr.usbap.sync가 설치돼 있으면 그쪽에 맡기고 이 모드는 하지 않습니다.
- 서비스가 멈추면(모드 끄기·제거) hostapd·dnsmasq를 끄고 backlog·송신 경로·전력을 되돌립니다. 드라이버는 재부팅할 때까지 남습니다.

## 파일
| 위치 | 내용 |
|---|---|
| `/data/hmgapi/run/usb-hotspot-kr/usbap/` | `usbap.log`(.old), `usbap.tune`, `usbap.netsample.txt`, `usbap.logcat.txt*`, `usbap.debug`(디버그 기록 켜짐, 0.1.3부터) |
| `/data/hmgapi/logs/usb-hotspot-kr/usbap.log` | 서비스 출력 (HMG-API가 보관) |
| `/data/local/tmp/ev6kr_usbap/` | `hostapd.conf`(600), `hostapd.pid`, `hostapd.log`, `iface`, `insmod.log`, `dhcp/`(dnsmasq 로그·임대) |

trylog 스틱(4판)이 이 파일들과 커널 설정, `ip rule`, `iptables -S`를 모읍니다. `EV6KR-TUNE.txt`와 `EV6KR-DEBUG-ON/OFF`도 이 모드의 파일에 적용됩니다(ev6kr.usbap.sync가 없을 때). 디버그 기록(logcat 파일, netsample)은 0.1.3부터 기본으로 꺼져 있고 `EV6KR-DEBUG-ON`으로 켭니다.

## 방화벽
모드는 `rtwlan+`의 송수신 허용 규칙을 선언합니다. 다만 HMG-API의 핫스팟 별칭(`wlan0`)이 아니라서 **차 주인의 허용이 있어야** 들어갑니다(`/data/hmgapi/settings/hmgapi.json`의 `"overrides": {"allow_network": ["usb-hotspot-kr"]}`).

국내형 EV6의 순정 방화벽이 `rtwlan`을 막는지는 아직 모릅니다. 그래서 허용 없이 먼저 시험하고, iPhone이 주소를 못 받거나 카플레이 연결이 안 되면 trylog의 `net-now.txt`(`iptables -S`)를 봅니다.

## 설치와 전환 (차에서)
기존 구성에서 독립 구성으로:
1. NEMESIS에서 **usbwifi.hotspot**과 **ev6kr.usbap.sync**를 제거합니다.
2. 재부팅합니다. usbwifi.hotspot이 올린 드라이버를 내리기 위해서입니다.
3. `dist/ev6kr-wireless-carplay-standalone-<v>-nemesis.zip`을 USB 루트에 풀고, 스토어에서 **USB Wi-Fi Hotspot (EV6 KR)**과 **Wireless CarPlay (EV6 KR, USB Wi-Fi)** 0.1.6 이상을 설치합니다.
4. 동글을 꽂고 카플레이를 연결합니다.

되돌리기: 이 모드를 제거하고 재부팅한 뒤 usbwifi.hotspot과 ev6kr.usbap.sync를 다시 설치합니다. 카플레이 모드 0.1.6은 두 구성 모두에서 동작합니다.

## 동글 뽑기 주의
이 드라이버로 핫스팟이 떠 있을 때 동글을 뽑으면 헤드유닛이 재부팅될 수 있습니다(9차 수집, 확인 중). 로그 스틱으로 바꿀 때는 차를 끄고 문을 열어 헤드유닛이 꺼진 뒤 바꾸고, 다시 켜서 스틱이 부팅 때 실행되게 하는 편이 안전합니다.

## 차량에서 아직 확인하지 않은 것
- 이 빌드의 드라이버로 동글을 뺄 때 커널이 버티는지(드라이버 README 참고)
- 순정 dnsmasq가 67번 포트에서 동작하는지(trylog의 `net-now.txt` udp 목록에 67번 `0043`을 쓰는 다른 프로세스가 있는지)
- 순정 방화벽이 `rtwlan`을 막는지
- 첫 시험은 **차를 세운 상태에서** 해 주세요.
