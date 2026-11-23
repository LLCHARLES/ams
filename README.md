<p align="right"><b>한국어</b> · <a href="README.en.md">English</a></p>

<p align="center">
  <img src="docs/icon.png" width="128" alt="Retrine 아이콘">
</p>

<h1 align="center">Retrine</h1>

<p align="center">
  <b>Liquid Glass로 다시 만든 iOS용 Spotify.</b><br>
  탈옥 없이, 직접 준비한 복호화된 Spotify IPA에 주입하는 트윅입니다.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Spotify-9.1.78%20%7C%209.1.88%20%7C%209.1.90%20%7C%209.2.0-1ED760?style=for-the-badge&logo=spotify&logoColor=white" alt="Spotify 9.1.78 | 9.1.88 | 9.1.90 | 9.2.0">
  <img src="https://img.shields.io/badge/Redesign-iOS%2026%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="재설계: iOS 26+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge" alt="라이선스: GPL-3.0"></a>
</p>

<p align="center">
  <a href="#직접-빌드하기">빌드</a> ·
  <a href="#서명과-번들-id">서명</a> ·
  <a href="#wireguard--프록시">WireGuard</a> ·
  <a href="docs/tweaks.md">개발 문서</a> ·
  <a href="https://github.com/oneulddu/Retrine/issues/new/choose">버그 제보</a>
</p>

<p align="center">
  <img src="docs/screenshots/now-playing.webp" width="16%" alt="가사가 표시된 전체 화면 플레이어">
  <img src="docs/screenshots/album.webp" width="16%" alt="앨범">
  <img src="docs/screenshots/playlist.webp" width="16%" alt="플레이리스트">
  <img src="docs/screenshots/queue.webp" width="16%" alt="재생 대기열">
  <img src="docs/screenshots/live-activity.webp" width="16%" alt="잠금 화면의 Live Activity">
  <img src="docs/screenshots/home.webp" width="16%" alt="홈">
</p>

> [!NOTE]
> **Retrine은 [Vitrine](https://github.com/My-Name-Is-Jeff/vitrine)의 포크입니다.**

## 소개

Retrine은 iOS용 Spotify를 Liquid Glass로 새로 단장하는 Theos 트윅(Objective-C + Logos)입니다. 직접
준비한 복호화된 Spotify IPA에 주입하고 본인 인증서로 서명해서 쓰기 때문에 탈옥이 필요 없습니다.

Retrine이 포크한 Vitrine은 Vojtěch Škopek의 [spoti.pw](https://github.com/skopevoj/spoti.pw)를 포크한
프로젝트입니다. GPL-3.0으로 공개된 마지막 버전인 0.21.1(커밋 `c790445`, 2026-09-23)에서 갈라져 나와
그 뒤로 계속 수정되었습니다.

**IPA는 배포하지 않습니다.** 직접 준비한 Spotify IPA로 브라우저에서 GitHub Actions를 돌리거나 Mac에서
직접 빌드하세요.

## 기능

모드 설정(Mod Settings) 맨 위의 **재설계 UI**(Redesigned UI) 스위치로 두 가지 화면 중 하나를 고릅니다.
이 설정은 앱을 실행할 때 한 번 읽습니다.

- **재설계(Redesign)**: 처음부터 새로 만든 Liquid Glass 화면입니다. 기본 화면용 트윅은 하나도 실행되지 않습니다.
- **Spotify 기본 화면**: Spotify 화면은 그대로 두고 그 위에 트윅을 얹습니다. 숨기기 스위치, 글래스 헤더
  버튼, 홈 그라데이션, AMOLED, 강조 색상 등을 쓸 수 있습니다.

Spotify 화면을 직접 그리지 않는 기능(광고, 개인정보 보호, 가사 소스, 제스처, 아티스트 차단, 진동, 속도와
피치, Live Activity)은 두 화면에서 똑같이 동작합니다. 모드 설정은 탭 바의 홈을 길게 누르거나, 사이드
메뉴의 첫 줄 또는 Spotify 설정의 맨 아래 줄에서 열 수 있습니다.

### 재설계: Liquid Glass와 Apple Music 스타일 플레이어

- 글래스 탭 바, 검색창, 재생 바와 탭 분리(Split Tabs)
- 새로 디자인한 전체 화면 플레이어와 가사 화면. Apple Music 스타일 가사가 늘 켜져 있고, 실시간 미리보기와
  스타일 프리셋(글자 크기, 줄 간격, 블러, 글로우, 웨이브)을 제공합니다
- 군더더기를 덜어낸 홈, 색을 입힌 글래스 위의 검색 카테고리, 큰 제목 하나로 정리한 보관함, 그리고 음악
  앱처럼 배치한 플레이리스트·앨범·아티스트 페이지(고정된 ⋯ 버튼이 시스템 메뉴를 엽니다)
- 전체 검은 배경과 별도 강조 색상(Spotify, Apple Music, 사용자 지정)

### iPad

- 가로 폭이 넓은(regular width) iPad에서는 확장 플레이어가 두 열로 나뉩니다. 한쪽에는 앨범 아트와
  컨트롤이, 다른 쪽에는 가사나 재생 대기열이 놓이며 가로·세로 방향 모두 같습니다
- 재생 바는 캡슐형 미니 플레이어가 되어 앨범 아트, 제목, 재생 버튼 옆에 셔플·반복·가사·대기열 버튼이 붙습니다

### 가사

- 여러 가사 소스를 순서대로 또는 한꺼번에 조회합니다: 가져온 가사(imported lyrics), Spicy Lyrics,
  BiniLyrics, LyricsPlus, Musixmatch, Unison, Deezer, NetEase, PetitLyrics, LRCLIB, Bugs, Genie,
  QQ Music, KuGou, Genius
- 소스가 지원하면 단어 단위 싱크를 씁니다. 재설계 화면에서는 플레이어의 ⋯에서 지금 재생 중인 곡의 가사
  소스를 바꿀 수 있습니다
- 발음 표기(라틴 문자 또는 한글, 일본어는 로마자 또는 히라가나)와 번역(Apple 번역, Apple Intelligence,
  본인 API 키를 쓰는 Gemini)
- 잠금 화면에 현재 가사 줄을 표시하고, iOS 26에서는 가사를 잠금 화면의 전체 화면 아트워크로 보여 줍니다
- 노래방(Karaoke): 기기에서 직접 곡의 보컬 소리를 줄여 줍니다

### 광고와 Premium 상태

- **광고 숨기기**, **업셀 숨기기**, **Premium 위장**(EeveeSpotify Reincarnated에서 가져옴). 첫 실행
  안내 화면의 **광고 없음** 스위치 하나로 세 가지를 한 번에 켤 수 있습니다
- Premium 위장을 켜면 DJ를 온전히 쓸 수 있고, 앨범 페이지에 **대기열에 추가**가 생깁니다

### 재생과 오디오

- 오디오 효과: 그래픽 EQ, 프리셋, AutoEq 헤드폰 보정, 리버브, 크로스피드 등
- Spotify 자체의 Automix와 크로스페이드를 한 페이지에서 설정, 속도와 피치 조절
- 진동: 컨트롤을 누를 때의 햅틱 피드백과 iOS 음악 햅틱(Music Haptics) 지원
- 플레이어의 더블 탭 영역, AirPods 머리 제스처
- 차단한 아티스트와 곡 건너뛰기, 팟캐스트용 SponsorBlock(기본값은 꺼짐)
- 기기에만 저장되는 청취 통계, 텔레메트리 차단, 공유 링크의 추적 정보 제거

### Live Activity

- 잠금 화면과 Dynamic Island(iOS 17 이상)에서 지금 부르는 가사 줄, 다음 곡 목록, 또는 재생 컨트롤·
  대기열·잠자기 타이머가 있는 컨트롤 화면 중 하나를 보여 줍니다

### 앱 내 WireGuard / 프록시

- Spotify 트래픽을 앱 안에서만 WireGuard나 프록시로 보냅니다. 직접 설정하기 전에는 꺼져 있으니
  먼저 [주의 사항](#wireguard--프록시)을 읽어 주세요

## 요구 사항

| | |
|---|---|
| Spotify | **9.1.78**, **9.1.88**, **9.1.90**, **9.2.0** 중 하나의 복호화된 IPA |
| 재설계 화면 | **iOS 26 이상** |
| Spotify 기본 화면 | iOS 16.1 이상 |
| Live Activity | iOS 17 이상 |
| WireGuard / 프록시 | Spotify 9.1.90 또는 9.2.0, 프록시 라우팅은 iOS 17 이상 |

이 모드는 Spotify 내부 클래스를 후킹하는데, 이 클래스들은 버전마다 바뀝니다. 그래서 다른 버전은 빌드는
되더라도 동작이 깨질 수 있습니다. 재설계 화면은 iOS 26부터 있는 `UIGlassEffect`를 씁니다. 그보다 낮은
버전에서는 테스트되지 않았다는 경고를 확인해야만 재설계 UI를 켤 수 있고, 재설계 화면으로 실행하다 멈추면
다음 실행은 Spotify 기본 화면으로 돌아갑니다. 이때도 모드의 나머지 기능은 그대로 유지됩니다.

## 직접 빌드하기

지원 버전의 복호화된 Spotify IPA가 필요합니다. 9.2.0을 기본 설정으로 빌드하면 `retrine-<version>-pixie.ipa`가 나오고,
이를 SideStore, Feather 등 원하는 서명 도구로 서명하면 됩니다.

릴리스에는 `.deb`도 없습니다. 트윅만 손으로 주입하면 재설계 화면에 필요한 앱 변경(글래스 탭 바),
Live Activity, 백그라운드 음악 햅틱, Connect 로컬 기기 검색이 빠지기 때문입니다. IPA로 빌드하세요.

### GitHub Actions로 빌드 (Mac 불필요)

1. 이 저장소를 포크하고, 포크한 저장소의 **Actions** 탭에서 Actions를 켭니다.
2. **Build IPA from your own Spotify IPA** 워크플로를 열고 **Run workflow**를 누릅니다.
3. 아래 입력값을 채우고 실행합니다.
4. 실행이 끝나면 해당 실행의 **Artifacts**에서 `retrine.ipa`를 내려받습니다.

| 입력값 | 기본값 | 설명 |
|---|---|---|
| Decrypted Spotify IPA URL | (필수) | 복호화된 IPA의 직접 다운로드 링크(Dropbox 공유 링크도 가능). 링크는 로그에서 가려집니다. |
| Where to put the result | `artifacts` | `artifacts`, `filebin`, `both` 중 선택. filebin을 고르면 실행 요약에 filebin.net 링크가 표시되며, 며칠 동안 쓰지 않으면 삭제됩니다. |
| Remove every app extension (PlugIns/) | 꺼짐 | IPA에서 앱 확장을 모두 제거합니다. [서명](#서명과-번들-id) 항목을 참고하세요. |
| Include app-local WireGuard / proxy | 켜짐 | **9.1.78과 9.1.88에서는 꺼야 합니다.** [WireGuard](#wireguard--프록시) 항목을 참고하세요. |
| Include Pixie native downloads | 켜짐 | 지원 대상인 9.2.0 또는 9.1.90 빌드와 정확히 일치해야 합니다. **9.1.78과 9.1.88에서는 꺼야 합니다.** |
| Bundle ID | `app.retrine.player` | 서명할 App ID와 같아야 하며, 앱 확장 ID도 이를 따라갑니다. Spotify의 ID를 유지하려면 `com.spotify.client`를 직접 입력합니다. [서명](#서명과-번들-id) 항목을 참고하세요. |

내려받은 파일은 먼저 검사하므로, HTML 로그인 페이지나 중간에 끊긴 파일이면 바로 실패합니다.

<details>
<summary><b>Mac에서 빌드</b></summary>

<br>

Theos를 `~/theos`에 설치하고, iPhoneOS 26 이상 SDK가 있는 Xcode를 `xcode-select`로 선택합니다.
`~/theos/sdks`의 SDK만 쓴다면 `PIXIE=0`으로 빌드해야 하며, Live Activity와 Open in Retrine 확장도 빠집니다.

```sh
brew install make ldid dpkg zsign libimobiledevice
uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw"
```

기본 IPA 빌드에는 WireGuard가 포함되며, `WireGuard/go.mod`에 고정된 Go 버전이 정확히 필요합니다.
`WIREGUARD=0`으로 빌드하면 WireGuard가 빠지고 Go도 필요 없습니다.

복호화된 `.ipa`를 `ipa/`에 넣고(`Spotify-9.2.0.ipa`가 있으면 그것을 먼저 쓰며, 다른 파일은 `IPA=`로
지정) 다음을 실행합니다.

```sh
make release                 # 9.2.0: out/retrine-<version>-pixie.ipa
make release PIXIE=0         # Pixie 제외: out/retrine-<version>.ipa
make release PIXIE=0 WIREGUARD=0  # 9.1.78 / 9.1.88에서는 둘 다 제외
make release NO_PLUGINS=1    # 앱 확장 모두 제거
make install                 # 빌드 후 본인 인증서로 서명해 기기에 설치
```

Mac에서 빌드하면 번들 ID를 따로 지정하지 않는 한 Spotify의 `com.spotify.client`가 유지됩니다. 바꾸려면
환경 변수로 지정합니다: `BUNDLE_ID=<본인 App ID> make release` (GitHub Actions 빌드의 기본값은
`BUNDLE_ID=app.retrine.player`입니다.)

`make install`은 `.signing.env`에서 `SIGN_P12`, `SIGN_PROFILE`, `SIGN_P12_PASSWORD`를 읽습니다.
`.signing.env.example`을 복사해 채워 넣으세요.

첫 빌드는 IPA에서 Spotify의 플래그를 읽느라 1분 정도 걸립니다. `make flags`로 다시 생성할 수 있습니다.

`scripts/pipeline.sh <ipa> --no-flex --keep-watch`를 쓰면 Spotify의 Apple Watch 앱을 남깁니다(**테스트되지
않음**). iPhone에서 복호화하면 arm64 빌드만 살아남기 때문에 Apple Watch Series 9, Ultra 2 이후 모델에서만
실행할 수 있고, Watch 앱 이름을 본인 App ID에 맞게 바꾸고 Watch가 포함된 별도 프로필로 서명해 주는 서명
도구가 필요합니다. `make install`은 아직 이를 지원하지 않습니다.

</details>

## 서명과 번들 ID

- **GitHub Actions 빌드의 기본 ID는 `app.retrine.player`입니다.** 정식 Spotify와 별개의 앱으로 설치됩니다.
- **Spotify의 ID(`com.spotify.client`)로 빌드하면** 정식 Spotify 위에 덮어 설치되어 이를 대체합니다. 무료
  Apple ID로 서명하면 그 ID가 본인 Apple 계정에 등록됩니다. 무료 계정의 서명이 막혔다는 제보가 최근
  늘었고 원인은 확인되지 않았지만, 그래서 기본값에서는 뺐습니다.
- **예전 기본값으로 설치한 앱이 있다면** 새 기본값으로 빌드한 IPA는 별개의 앱으로 설치되어 로그인과
  설정, 다운로드가 넘어오지 않습니다. 기존 앱을 그대로 업데이트하려면 `com.spotify.client`를 직접 입력하세요.
- **번들 ID는 인증서의 App ID와 같아야 합니다.** 앱 확장 ID도 이를 따라갑니다. 일치하지 않아도
  앱은 동작하지만 잠금 화면의 플레이어를 눌러도 앱이 열리지 않으며, 첫 실행 때 어떤 ID를 써야 하는지
  알려 줍니다.
- Feather에서는 App ID를 **Identifier**에 붙여 넣고 **PPQ protection**은 꺼 두세요. AltStore, SideStore,
  Sideloadly는 알아서 맞춰 줍니다.
- **무료 Apple ID**는 등록할 수 있는 App ID 수가 제한되어 있고 앱 확장마다 App ID가 하나씩 필요하므로,
  대개 **Remove every app extension**을 켜야 합니다. 이 경우 Live Activity, Open in Retrine 공유 동작,
  Spotify 자체의 위젯·Siri·알림 확장도 함께 빠집니다.
- 무료 Apple ID 서명은 7일 동안 유효합니다. 만료 날짜는 모드 설정에서 확인할 수 있습니다.

## WireGuard / 프록시

> [!WARNING]
> 이 기능은 **누출을 완전히 막아 주는 VPN도, 기기 전체에 적용되는 VPN도 아닙니다.** 검토된 Spotify
> 경로만 터널이나 프록시로 보내고, 그럴 수 없을 때는 보호 대상 경로를 차단합니다. 보안 경계로 여기지 마세요.

- 빌드에는 기본으로 포함되지만, `.conf`를 가져오거나 프록시를 저장하고, 직접 켠 뒤 Spotify를 다시
  시작하기 전까지는 꺼져 있습니다.
- 적용되지 않는 경로: 백그라운드 세션, 웹 로그인, AVURLAsset, 트윅 초기화 전의 트래픽, 로컬 네트워크
  예외, 다른 Connect 기기에서의 재생.
- WireGuard는 **Spotify 9.1.90과 9.2.0만** 지원합니다. 9.1.78이나 9.1.88은 `PIXIE=0 WIREGUARD=0`으로
  빌드하세요(Actions에서는 **Include Pixie native downloads**와 **Include app-local WireGuard / proxy**를 모두 해제).
- WireGuard 없이 빌드하면 이전에 켜 두었더라도 라우팅과 차단이 전혀 적용되지 않습니다.

적용 범위와 한계 전체: [docs/wireguard.md](docs/wireguard.md)

## Pixie 네이티브 다운로드 (실험적)

IPA에는 Pixie의 네이티브 다운로드 관리자가 기본으로 포함됩니다. 지원 대상인 Spotify 9.2.0 또는
9.1.90 빌드와 정확히 일치해야 합니다. 제외하려면 `PIXIE=0`을 지정하세요(파이프라인에서는 `--no-pixie`).
9.2.0에서는 다운로드, 앱 재시작 후 다운로드 유지, 삭제를 실기기에서 확인했습니다.
장기 오프라인 라이선스 갱신은 아직 확인하지 않았습니다.
지원 빌드와 제한 사항은 [docs/pixie.md](docs/pixie.md)(영문)를 참고하세요.

## 업데이트

**모드 설정 → 모드 → 업데이트**는 이 저장소의 [GitHub Releases](https://github.com/oneulddu/Retrine/releases)를
확인해 더 새로운 릴리스의 변경 내역을 모두 보여 줍니다. 새 릴리스가 나오면 Spotify를 연 지 몇 초 뒤에
릴리스당 한 번 안내 시트가 뜹니다. 베타는 **베타 포함**이 켜져 있을 때만 확인합니다(베타 빌드에서는
기본으로 켜짐).

릴리스에는 IPA가 첨부되지 않습니다. 업데이트하려면 포크를 동기화(Sync fork)한 뒤 워크플로를 다시 실행하거나,
Mac에서 최신 코드를 받아 `make release`를 실행하세요.

## 버그 제보와 기능 제안

이 저장소의 [Issues](https://github.com/oneulddu/Retrine/issues/new/choose)에서 **Bug report** 또는
**Feature request** 템플릿을 골라 작성해 주세요. 모드와 Spotify 버전은 **모드 설정 → 모드**에 있고, 같은
페이지의 **설정 내보내기** 파일을 첨부하면 특정 설정에서만 생기는 버그를 훨씬 쉽게 찾을 수 있습니다.

## 개발자용 문서

- [docs/tweaks.md](docs/tweaks.md): 프로젝트 구조, 레이어, 각 기능의 동작 방식
- [AGENTS.md](AGENTS.md): 코드 규칙 요약
- [docs/wireguard.md](docs/wireguard.md): WireGuard / 프록시 설계와 검증

## 크레딧

- 원작 프로젝트: Vojtěch Škopek의 [spoti.pw](https://github.com/skopevoj/spoti.pw)
- Retrine이 포크한 프로젝트: [Vitrine](https://github.com/My-Name-Is-Jeff/vitrine)
- 주입은 [cyan](https://github.com/asdfzxcvbn/pyzule-rw), 빌드는 [Theos](https://theos.dev)가 맡고,
  화면 구조(view tree)는 [FLEX](https://github.com/FLEXTool/FLEX)(`vendor/`에 있는 hopeless의 AutoFLEX
  빌드)로 살펴봅니다
- 광고 차단과 Premium 상태는 [EeveeSpotify Reincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)에서 가져왔습니다
- Pixie 네이티브 다운로드는 [Glongq/Vitrine-Pixie](https://github.com/Glongq/Vitrine-Pixie)에서 가져왔습니다.
  자세한 출처는 [docs/pixie.md](docs/pixie.md)를 참고하세요
- 오디오 효과에 쓰인 서드파티 코드와 라이선스는 [vendor/audio](vendor/audio/README.md)에 정리되어 있습니다

## 라이선스

[GPL-3.0](LICENSE). Spotify와는 관련이 없습니다.
