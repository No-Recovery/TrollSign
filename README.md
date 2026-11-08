# TrollSign 2.3

Личная SwiftUI-утилита для подписи и установки IPA на iPhone. Подписывает IPA
вашим сертификатом (`zsign`), затем устанавливает его через HTTPS
`itms-services`.

**Быстрый старт:** `Apps → +` → выберите `.ipa` → приложение подпишет его
активным сертификатом и установит. Готовый хостинг уже включён — токен и
настройка не нужны.

---

## Что нового в 2.3

- **Ready hosting** — хостинг работает сразу, без аккаунта и токена.
  Подписанный IPA и install-манифест автоматически загружаются на публичный
  HTTPS-хост, после чего открывается `itms-services`.
- **Liquid Glass** — стеклянные панели, плавающий таб-бар, градиентный фон и
  системный Liquid Glass на iOS 26+.
- **Сертификаты спрятаны сильнее** — отдельной вкладки и пункта в настройках
  больше нет. Долгое нажатие (0.55 с) на **нижний значок Settings** открывает
  экран сертификатов.
- **Respring** — кнопка в Settings → Maintenance, как в TrollStore (через
  `SBSRelaunchAction` / `FBSSystemService`).
- **GitHub hosting остался** — можно публиковать в свой репозиторий, но это
  уже необязательно.

---

## Где сертификаты

1. Откройте приложение.
2. Зажмите **нижний значок Settings** в плавающем таб-баре примерно на
   0.55 секунды.
3. Откроется экран **Certificates**: добавьте `.p12` + `.mobileprovision`,
   выберите активный сертификат.
4. Там же — необязательный локальный HTTPS-сервер (`localhost.direct`).

Никаких подсказок «Certificates hidden again» в Settings больше нет.

---

## Хостинг

### Ready hosting (по умолчанию)

Ничего настраивать не нужно. При установке:

1. IPA подписывается выбранным сертификатом.
2. IPA загружается на публичный HTTPS-хост (catbox.moe).
3. Рядом создаётся install-манифест `.xml`.
4. iOS открывает `itms-services://` и устанавливает приложение.

Ограничение: файл до 200 МБ. Ссылки публичные (но не индексируются), поэтому
не загружайте приватные приложения, если это критично.

### GitHub hosting (опционально)

`Settings → Hosting → GitHub hosting`. Поля уже заполнены:

| Поле | Значение по умолчанию |
|---|---|
| Owner | `No-Recovery` |
| Repository | `TrollSign` |
| Branch | `main` |
| Pages URL | `https://no-recovery.github.io/TrollSign/` |
| Token | хранится только в iOS Keychain |

Что делает приложение:

1. Проверяет репозиторий.
2. Включает Pages: ветка `main`, папка `/docs`.
3. Создаёт GitHub Release `ipa-<timestamp>`.
4. Загружает подписанный IPA как asset.
5. Кладёт `docs/manifests/<uuid>.xml`.
6. Ждёт публикации Pages и открывает `itms-services`.

Токен нужен только для GitHub hosting:

- classic: scope **repo**;
- fine-grained: **Contents**, **Releases**, **Pages** read/write, плюс
  **Administration**, если TrollSign должен создавать репозиторий.

Токен вводится в приложении и хранится в Keychain. В исходниках и в Git его нет.

### Локальный сервер (запасной вариант)

`Settings` (долгое нажатие) → `Certificates` → `Local Installation Server`.
Нужен `server.p12` для `localhost.direct` (или своего домена на `127.0.0.1`).
Используется только если вы вызываете локальную установку вручную.

---

## Respring

`Settings → Maintenance → Respring` перезапускает SpringBoard тем же приватным
путём, что TrollStore:

- `SBSRelaunchAction("restartRenderServer", …)`;
- `FBSSystemService sendActions:withResult:withError:`;
- запасной вариант — `killall -9 SpringBoard`.

На сборке с обычным сертификатом система может отклонить запрос — тогда
TrollSign покажет сообщение. На TrollStore / platform-application сборке
respring работает.

---

## Сборка

### GitHub Actions (без Mac)

Workflow `.github/workflows/build.yml` на `macos-15`:

- ставит XcodeGen;
- генерирует `TrollSign.xcodeproj` из `project.yml`;
- собирает `TrollSign.app` под `iphoneos` без подписи;
- упаковывает `TrollSign.ipa`;
- публикует релиз `latest` и artifacts.

Скачать:

`https://github.com/No-Recovery/TrollSign/releases/latest/download/TrollSign.ipa`

### Локально на macOS

```bash
brew install xcodegen
xcodegen generate
open TrollSign.xcodeproj
```

Выберите свою команду/профиль для подписи. Минимальная версия iOS — **16.0**.

---

## Структура

```
TrollSign/
├── project.yml                 # XcodeGen-спецификация (iOS 16+)
├── TrollSign/
│   ├── TrollSignApp.swift      # точка входа, кастомный таб-бар
│   ├── Theme.swift             # Liquid Glass: фон, панели, таб-бар
│   ├── AppsView.swift          # список IPA, установка, детали
│   ├── SettingsView.swift      # настройки, хостинг, maintenance, respring
│   ├── CertificatesView.swift  # сертификаты + локальный сервер
│   ├── Hosting.swift           # Ready hosting (catbox) + выбор провайдера
│   ├── HostingView.swift       # экран настройки хостинга
│   ├── GitHubHosting.swift     # GitHub API, Releases, Pages, манифест
│   ├── Installer.swift         # ready/github/локальная установка
│   ├── Signer.swift            # zsign: unzip → sign → zip
│   ├── Respring.swift          # SBSRelaunchAction / killall
│   ├── Stores.swift            # AppStore, CertStore
│   ├── LocalServer.swift       # локальный HTTPS-сервер
│   ├── Models.swift
│   ├── Keychain.swift
│   ├── KeepAlive.swift
│   ├── DocumentPicker.swift
│   ├── Info.plist
│   └── Assets.xcassets
├── docs/                       # GitHub Pages (лендинг + manifests/)
└── .github/workflows/build.yml # сборка unsigned IPA на macOS
```

## Зависимости

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — распаковка/упаковка IPA.
- [zwsn/zsign-ios](https://github.com/zwsn/zsign-ios) — настоящий zsign + OpenSSL
  (`ZSignApple`, модуль `ZSign`). Подписывается распакованная папка `.app`,
  поэтому `Signer.swift` делает unzip → `zsign(...)` → zip.

## Важно

- iOS ставит приложения по `itms-services` только по **HTTPS с доверенным
  сертификатом**; Ready hosting и GitHub Pages это условие выполняют.
- Для dev-профиля UDID устройства должен быть добавлен в профиль.
- Это не TrollStore и не устанавливает неподписанные приложения «в обход»
  системы: приложение подписывает IPA вашим сертификатом.
- Ready hosting использует catbox.moe. Если сервис недоступен, переключитесь на
  GitHub hosting.
