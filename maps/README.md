# 국내형 EV6 훅 맵

`kia/ev6/kor/260902/`: HMG-API `tools/map-car.py`로 국내형 EV6(`CVEV.KOR.`, 260902) 순정 파일에서 만든 훅 맵입니다.
훅 지점 이름과 순정 파일 md5만 들어 있고, 앱 코드는 없습니다.

```sh
cd ../HMG-API
python3 tools/map-car.py ~/hmg-private/stock/ev6_kr --make kia --model ev6 --region kor --firmware 260902 \
    --products CVEV.KOR. --name "Kia EV6 (Korea)" --maps ../ev6kr-wireless-carplay/maps
```

HMG-API는 모드 안에 맵을 넣어 배포하는 방법이 없고, 코어를 설치하거나 업데이트하면 `/data/hmgapi/maps`가 통째로 바뀝니다.

- **권장 방법**: 차량에서 HMG-API 앱의 *Map this car from its files*와 *Check the map on this car*를 실행합니다.
- **이 맵을 쓰는 방법**: adb로 `/data/hmgapi/maps/kia/ev6/kor/260902/`에 복사한 뒤 `hmgapid engine verify-map`을 실행합니다. 상태가 `mapped`라서, 차량에서 검증을 통과하기 전에는 훅이 켜지지 않습니다.
