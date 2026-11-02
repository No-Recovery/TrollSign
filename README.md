# TrollSign 2.2

Личная SwiftUI-утилита для подписи и установки IPA на iPhone.

**Что делает:** `Apps → +` → выбор `.ipa` → подпись сертификатом (zsign) → установка.

Есть два способа доставки подписанного IPA на устройство:

1. **GitHub Hosting (новое, рекомендуется)** — IPA загружается в GitHub Releases, рядом
   создаётся `manifest.plist` в GitHub Pages, установка идёт по HTTPS через
   `itms-services`. Не нужен ни локальный сервер, ни сертификат для `localhost.direct`.
2. **Локальный HTTPS-сервер** — как раньше: `localhost.direct` (или свой домен,
   указывающий на `127.0.0.1`) + импортированный `server.p12`.

---

## Где теперь сертификаты (скрытая вкладка)

Отдельной вкладки **Certs больше нет**. Она перенесена внутрь **Settings**:

1. Откройте **Settings**.
2. Сделайте **долгое нажатие (1.5 с)** на строку **«TrollSign 2.2»** в самом низу.
3. Появится раздел **Advanced → Certificates**.

Там же: список сертификатов, `+` для добавления `.p12` + `.mobileprovision`,
выбор активного сертификата и настройки **Local Installation Server**
(host / port / server.p12 / Test Server).

Повторное долгое нажатие снова прячет раздел.

---

## GitHub Hosting

Открывается: **Settings → GitHub Hosting**.

Поля:

| Поле | Значение по умолчанию |
|---|---|
| Owner | `No-Recovery` |
| Repository | `TrollSign` |
| Branch | `main` |
| Pages URL | `https://no-recovery.github.io/TrollSign/` |
| Token | хранится только в iOS Keychain |

Что делает приложение при установке:

1. Проверяет репозиторий (если его нет — создаёт публичный репозиторий).
2. Включает GitHub Pages: ветка `main`, папка `/docs`.
3. Создаёт GitHub Release `ipa-<timestamp>`.
4. Загружает подписанный IPA как asset релиза.
5. Кладёт `docs/manifests/<uuid>.plist` через Contents API.
6. Ждёт, пока Pages опубликует манифест, и открывает `itms-services://`.

### Токен

Нужен **personal access token** (не пароль):

- classic: scope **repo**;
- fine-grained: **Contents: Read and write**, **Releases: Read and write**,
  **Pages: Read and write**, **Administration: Read and write** (для создания репозитория).

Токен вводится в приложении и хранится в Keychain. В исходниках и в Git его нет.

### Публичная страница

`https://no-recovery.github.io/TrollSign/` — лендинг с кнопкой скачивания
последней unsigned-сборки и инструкцией.

Сами манифесты, которые создаёт приложение, лежат по адресу
`https://no-recovery.github.io/TrollSign/manifests/<uuid>.plist`.

---

## Структура

```
TrollSign/
├── project.yml                 # XcodeGen-спецификация (iOS 16+)
├── TrollSign/
│   ├── TrollSignApp.swift      # точка входа, URL-схемы
│   ├── AppsView.swift
│   ├── SettingsView.swift      # скрытый вход в Certificates + GitHub Hosting
│   ├── CertificatesView.swift  # сертификаты + локальный сервер
│   ├── GitHubHosting.swift     # GitHub API, Releases, Pages, манифест
│   ├── Installer.swift         # GitHub Pages или локальный сервер
│   ├── Signer.swift            # zsign: unzip → sign → zip
│   ├── Stores.swift
│   ├── LocalServer.swift
│   ├── Models.swift
│   ├── Keychain.swift
│   ├── KeepAlive.swift
│   ├── DocumentPicker.swift
│   ├── Info.plist
│   └── Assets.xcassets
├── docs/                       # GitHub Pages (лендинг + manifests/)
└── .github/workflows/build.yml # сборка unsigned IPA на macOS
```

## Сборка

### Через GitHub Actions (без Mac)

Workflow `.github/workflows/build.yml` запускается на `macos-15`:

- ставит XcodeGen;
- генерирует `TrollSign.xcodeproj` из `project.yml`;
- собирает `TrollSign.app` под `iphoneos` без подписи;
- упаковывает `TrollSign.ipa`;
- публикует релиз `latest` и artifacts.

Скачать: `https://github.com/No-Recovery/TrollSign/releases/latest/download/TrollSign.ipa`

### Локально на macOS

```bash
brew install xcodegen
xcodegen generate
open TrollSign.xcodeproj
```

В Xcode выберите свою команду/профиль для подписи. Минимальная версия iOS — **16.0**
(используется `NavigationStack`).

## Зависимости

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — распаковка/упаковка IPA.
- [zwsn/zsign-ios](https://github.com/zwsn/zsign-ios) — настоящий zsign + OpenSSL
  (`ZSignApple`, модуль `ZSign`). Подписывается распакованная папка `.app`,
  поэтому `Signer.swift` делает unzip → `zsign(...)` → zip.

## Важно

- iOS ставит приложения по `itms-services` только по **HTTPS с доверенным
  сертификатом**; GitHub Pages это условие выполняет.
- Для dev-профиля UDID устройства должен быть добавлен в профиль.
- Это не TrollStore и не устанавливает неподписанные приложения «в обход»
  системы: приложение подписывает IPA вашим сертификатом.
