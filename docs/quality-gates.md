# Контур качества Kanki

Единственный регламент проверок. Локальный `./scripts/ci.sh` остаётся полным контуром;
per-PR CI намеренно не запускает iOS UI-тесты, чтобы не тратить ~13 минут на каждый пуш.
Если команда здесь отсутствует, она не является обязательной.

## Команды

| Проверка | Команда | Что означает |
| --- | --- | --- |
| Всё сразу | `./scripts/ci.sh` | Полный контур: линтеры, unit-тесты с порогом, iOS UI-тесты, macOS UI-тест |
| Swift | `./scripts/lint.sh swift` | `swiftlint lint --strict` по `.swiftlint.yml` |
| Markdown | `./scripts/lint.sh markdown` | `markdownlint-cli2` по `.markdownlint-cli2.jsonc` |
| Unit + покрытие | `./scripts/test.sh` | `xcodegen generate`, тесты `KankiTests`, порог покрытия |
| UI | `./scripts/ui-test.sh` | UI-тесты `KankiUITests` на симуляторе; локально и перед релизом, не в per-PR CI |
| macOS | `./scripts/macos-ui-test.sh` | Сборка native macOS-приложения и `KankiMacUITests`: окно и ⌘1–⌘4 |
| Покрытие отдельно | `python3 scripts/coverage_gate.py` | Разбор `build/Test.xcresult` через `xcrun xccov` |

Требования к среде: macOS, Xcode с iOS Simulator runtime, XcodeGen 2.46.0,
SwiftLint 0.65.1 или новее (`brew install swiftlint`), Node 22 для `npx` (Markdown),
Python 3 (скрипты без сторонних пакетов).

## Покрытие: порог 95 %

- Порог действует на **`Kanki/Domain/**`** и составляет **95 % строк**.
- `scripts/coverage_gate.py` читает отчёт `xcrun xccov` и завершается с кодом 1,
  если покрытие ниже порога, и с кодом 2, если файлов домена нет в отчёте или хотя бы
  один файл с диска отсутствует в `project.pbxproj` (забыли `xcodegen generate`).
  Состав сверяется с проектом, а не с отчётом: чистые записи без исполняемых строк
  (`SessionReview`) в отчёт `xccov` не попадают. Строки одного файла, попавшего
  в несколько таргетов, не учитываются дважды.
- `scripts/test.sh` запускает только `KankiTests` (`-only-testing:KankiTests`),
  поэтому цифра отражает именно unit-тесты.
- `scripts/ui-test.sh` запускает UI-тесты с `-enableCodeCoverage NO`: строки
  приложения под UI-тестом не собираются в отчёт, а инструментированный прогон
  на симуляторе дольше и чаще падает с `Test crashed with signal kill`.
  Порог считается только по unit-прогону.
- Почему не всё приложение: `Kanki/Views/**` — декларативные `body` SwiftUI.
  Их покрытие строками требует snapshot- или ViewInspector-подхода, которого в проекте
  нет и который не ловит реальные регрессии вёрстки; пользовательские пути проверяются
  XCUITest. Отчёт печатает справочное покрытие всего таргета — оно не влияет на результат.
- **Правило разработки:** любая нетривиальная логика (состояние, преобразования,
  валидация, расчёты, порядок элементов) живёт в `Kanki/Domain` и покрывается
  unit-тестами в том же PR. В представлениях допустимы только вёрстка и локальные
  флаги показа.
- Новый файл в `Kanki/Domain` обязан попасть под порог автоматически: фильтр по пути,
  список файлов вручную не ведётся.
- Понижать порог или менять `--scope` можно только отдельным issue с обоснованием;
  правка без обновления этого файла и `AGENTS.md` каталога считается ошибкой.

## Линтеры

### SwiftLint

- Конфигурация `.swiftlint.yml`: `strict: true`, явный список `opt_in_rules`.
  Явный список выбран намеренно: обновление SwiftLint не включает новые правила
  незаметно и не ломает CI.
- Нарушения не подавляются `// swiftlint:disable` без комментария с причиной.
- Стиль: `line_length` 160/200 (длинные русские строки), `file_length` 400/500.
- Ошибка линтера = красный CI. Не отключайте правило ради прохождения сборки.

### markdownlint-cli2

- Конфигурация `.markdownlint-cli2.jsonc`, версия `0.24.0` закреплена в `scripts/lint.sh`.
- Отключены: `MD013` (перенос русской прозы по 80 символам бессмысленен),
  `MD033` (HTML-комментарии в шаблонах issue/PR), `MD041` (шаблоны начинаются
  с комментария или служебного поля). `MD024` работает в режиме `siblings_only`.
- Автоисправление: `npx --yes markdownlint-cli2@0.24.0 --fix`, затем повторный прогон
  и просмотр диффа.

## CI

`.github/workflows/ci.yml` — четыре задания:

| Задание | Раннер | Шаги |
| --- | --- | --- |
| Markdown | `ubuntu-latest` | `./scripts/lint.sh markdown` |
| SwiftLint | `macos-latest` | `brew install swiftlint`, `./scripts/lint.sh swift` |
| Tests | `macos-latest` | `brew install xcodegen`, `xcodegen generate`, `git diff --exit-code -- Kanki.xcodeproj`, `./scripts/test.sh` |
| macOS | `macos-latest` | `brew install xcodegen`, `xcodegen generate`, `git diff --exit-code -- Kanki.xcodeproj`, `xcodebuild build -destination 'platform=macOS'`, `./scripts/macos-ui-test.sh` |

- Запуск: `pull_request` в `dev`/`main`, `push` в `dev`; `concurrency` отменяет
  устаревшие прогоны той же ветки.
- iOS UI-тесты (`./scripts/ui-test.sh`) не входят в per-PR CI: они долгие и нестабильны на общем раннере. Запускайте их локально при изменениях пользовательских путей и перед релизом `dev` → `main`.
- Права минимальные (`contents: read`), секреты не используются.
- При падении сохраняются `build/*.xcresult` как артефакт (7 дней).
- Зелёный CI обязателен перед merge. Отключение шага, `continue-on-error` или
  `|| true` ради прохождения запрещены.

## Единые правила разработки

- Любое изменение начинается с GitHub issue и рабочей ветки от `origin/dev`
  (`feature/`, `fix/`, `docs/`), заканчивается PR в `dev`. См. `CONTRIBUTING.md`.
- Новый, переименованный или удалённый файл в `Kanki/` требует
  `xcodegen generate`; результат `Kanki.xcodeproj` коммитится вместе с изменением.
- Типы домена — `internal`, иначе `@testable import Kanki` их не увидит.
- UI-текст — русский, идентификаторы, символы и коммиты — английский.
- Демо-данные помечаются как демо; нереализованное поведение не показывается успешным.
- Новая зависимость, слой или скрипт появляются вместе с потребляющим их поведением.
- Секреты, Team ID, UDID, приватные заметки и коллекции Anki не попадают
  в репозиторий, issue, PR и логи.

## Изменение контура

1. Заведите issue с причиной (новая проверка, порог, правило линтера).
2. Измените конфиг или скрипт; держите версии инструментов закреплёнными.
3. Обновите этот файл и `AGENTS.md` затронутого каталога.
4. Прогоните `./scripts/ci.sh` и приложите фактический вывод в issue/PR.

## Диагностика

| Симптом | Что делать |
| --- | --- |
| `Test crashed with signal kill` | `xcrun simctl shutdown <id>`, затем `xcrun simctl boot <id>` и повторить |
| `signal kill` повторяется после прерванной сборки | `rm -rf build/DerivedData` и повторить: неполные продукты в DerivedData ломают запуск test-runner |
| Нет доступного симулятора | Установить iOS Simulator runtime в Xcode Settings → Components |
| `xccov` не находит данные покрытия | В `Kanki.xcodeproj/xcshareddata/xcschemes/Kanki.xcscheme` проверить `codeCoverageEnabled="YES"` и `CodeCoverageTargets`, в `project.yml` — `gatherCoverageData: true`; отдельный флаг `-enableCodeCoverage` не нужен, покрытие включает схема |
| `SwiftLint не установлен` | `brew install swiftlint` |
| Markdown-нарушения | `npx --yes markdownlint-cli2@0.24.0 --fix`, затем проверить дифф |

## Версии

Xcode 27.2 (минимум 26.3), XcodeGen 2.46.0, SwiftLint 0.65.1+, markdownlint-cli2 0.24.0,
Node 22, Python 3. `.github/workflows/ci.yml` использует `macos-latest` и ставит
SwiftLint/XcodeGen из Homebrew; версии правил закреплены конфигурацией.
