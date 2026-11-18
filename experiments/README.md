# Э1: проверка обмена с AnkiDesktop

Здесь протокол и результаты Э1; утверждённый профиль описан в [контракте обмена Anki v1](../docs/anki-exchange-v1.md). Используйте отдельный временный профиль Anki, без личной коллекции.

## Подготовка

Для автоматического прогона нужен `uv`; для ручной проверки — AnkiDesktop. Пакеты генерируются вне репозитория (не коммитьте `.apkg` с личными данными):

```bash
uv run --no-project --with genanki==0.13.1 python experiments/e1.py generate /tmp/kanki-e1
uv run --no-project --with genanki==0.13.1 --with zstandard python experiments/e1.py inspect /tmp/kanki-e1/test1.apkg
uv run --no-project --with anki==26.09.3 --with zstandard python experiments/e1_roundtrip.py /tmp/kanki-e1
uv run --no-project --with zstandard python experiments/e1_restore.py /tmp/kanki-e1/test3.apkg /tmp/kanki-e1/test2.apkg /tmp/kanki-e1/restored.sqlite
```

`e1_roundtrip.py` создаёт временную чистую коллекцию, импортирует через backend Anki 26.09.3, отвечает Good, экспортирует `test2.apkg` с историей и проверяет обновление/повторный импорт/конфликт типа, связи и `(guid, ord)`. Затем `e1_restore.py` восстанавливает **обновлённый контент из `test3.apkg`** и **прогресс из `test2.apkg`** в отдельную SQLite-БД (`notes`, `cards`, `edges`, `review_log`), включая канонические и вычисленные рёбра; существующий файл он не перезаписывает. Для отдельной команды выше нужен уже созданный `test2.apkg`, а путь `restored.sqlite` не должен существовать. Это экспериментальная схема, не БД приложения и не полноценный конвертер обменного формата. В Anki 26.09.3 данные находятся в сжатом `collection.anki21b`; `collection.anki2` в том же пакете — служебный legacy-плейсхолдер.

`test1.apkg` содержит две заметки/карточки, UID первым полем, одну связь `…0004 requires …0001`. `test3.apkg` сохраняет GUID и ID нотетайпа, но увеличивает `mod`, меняет Body и Relations заметки `…0001`; обе заметки в пакете получают новый `mod`. `test4-type-change.apkg` — отрицательный контроль: тот же GUID заметки `…0001`, другой нотетайп с дополнительным полем.

## Ручной прогон (отметить фактические результаты в issue #3)

1. Импортировать `test1.apkg` в **пустой временный профиль** AnkiDesktop: проверить 2 заметки, 2 карточки, читаемые Q/A и Relations.
2. Ответить Good на обе карточки. Сверить due, interval и записи истории до и после оценки: в состоянии Learning due может перейти на Unix-время, а `cards.ivl` остаться `0`; отрицательный интервал revlog означает секунды, не дни.
3. Экспортировать колоду как `/tmp/kanki-e1/test2-gui.apkg` **с историей повторений** (`Include scheduling information` в Anki 26.09.3). Проверить: `uv run --no-project --with genanki==0.13.1 --with zstandard python experiments/e1.py inspect /tmp/kanki-e1/test2-gui.apkg`. Сопоставить guid и ord; сверить revlog и due/interval. Это выход GUI AnkiDesktop, не genanki и не backend-прогон.
4. Импортировать `test3.apkg` с включённым `Import any learning progress` (название в Anki 26.09.3). Проверить число обновлённых/добавленных заметок, Body/Relations, due/interval и revlog **до и после**. Этот переключатель управляет импортом истории из пакета; сохранение уже имеющегося прогресса доказывает только сравнение данных, а не переключатель или отчёт импорта.
5. Импортировать `test3.apkg` ещё раз: проверить отсутствие дублей и повторных изменений. Импортировать `test4-type-change.apkg`: зафиксировать фактическую реакцию на несовпадающий нотетайп, число добавленных/обновлённых заметок и состояние исходной.
6. Извлечь Relations из `test2-gui.apkg` через `inspect` и проверить каноническое ребро `…0004 requires …0001`; вычисленная обратная проекция `required_for` строится индексом приложения, её нет в .apkg. Сопоставить карты по `(guid, ord)`.

**Успех Э1:** нет дублей, прогресс не потерян, UID/GUID и связи восстановимы, конфликт типа обработан предсказуемо. Если любое ожидание расходится с фактом — записать расхождение, а не менять продуктовый контракт молча. Экспериментальная SQLite-БД проверяет восстановление `(guid, ord)` и Relations отдельно от продуктового хранилища Kanki.

## Фактические результаты

Backend Anki 26.09.3 (2026-11-01): 2 заметки, 2 карты, 2 Good, 2 обновления, повторный импорт без изменений, один конфликт типа без потери прогресса. Экспериментальное восстановление перенесло контент, четыре ребра и прогресс, а пакет со сменой типа отклонило.

AnkiDesktop 26.09.3 (`aqt` и `anki` из PyPI, 2026-11-18): полный GUI-сценарий пройден на macOS arm64, в изолированном `uv`-окружении с временными `HOME` и `-b`. Qt offscreen получил события мыши и клавиатуры в штатных окнах, включая диалоги выбора файлов, импорта и экспорта. Для сравнения данных использовалось чтение SQLite, не вызовы backend вместо GUI. [Отчёт о прогоне в #3](https://github.com/EgorYolkin/kanki/issues/3#issuecomment-6974240772).

| Шаг | Наблюдение |
| --- | --- |
| `test1.apkg` | 2 Added, 2 карточки. В режиме повторения прочитаны оба вопроса, оба ответа и `…0004 requires …0001`. |
| Два Good | Обе карты перешли из New в Learning. Due изменился, `cards.ivl` остался `0`, в revlog две строки с `ease=3` и `ivl=-600` (10 минут). |
| `test2-gui.apkg` | Экспорт выбранной колоды с расписанием содержит `collection.anki21b`: совпали `(guid, ord)` (у обеих карт `ord=0`), due/interval, очередь, revlog и Relations. |
| `test3.apkg` | 2 Updated, 0 Added. Body и `related` у `…0001` обновились, `requires` у `…0004` сохранилась. GUID, ID нотетайпа, расписание и revlog совпали до и после. |
| Повторный `test3.apkg` | 2 Skipped, 0 Updated, 0 Added. Снимки заметок, расписания и revlog совпали. |
| `test4-type-change.apkg` | `1 note could not be imported`, 1 Skipped, 0 Updated, 0 Added. Заметки, расписание и revlog не изменились. |
| Восстановление | `e1_restore.py` взял контент из `test3.apkg`, прогресс из `test2-gui.apkg`. В экспериментальной SQLite-БД совпали два UID, `SchemaVersion=1`, расписание и две строки revlog по `(guid, ord)`; восстановлены четыре ребра, из них два производных. |

Оффскрин-прогон не проверяет нативную отрисовку или официальный DMG. Этот прогон не открывал продуктовую БД; её проверили отдельно в [#150](https://github.com/EgorYolkin/kanki/pull/150).
На момент GUI-отчёта этап ещё не был принят и контракт не был утверждён.
Последующие результаты — ниже, итоговое решение — в [контракте v1](../docs/anki-exchange-v1.md).

## Проверка продуктового хранилища

В [#149](https://github.com/EgorYolkin/kanki/issues/149) `.apkg` читает
внешний адаптер `e1_product_input.py`. Он извлекает фактический порядок
полей, заметки и карты; для пакета с историей также извлекает расписание
и revlog. NID/CID служат только для соединения строк внутри исходного пакета.
Адаптер не пишет БД Kanki. JSON на его выходе — внутренний вход этого
среза, не публичный формат обмена и не универсальный импорт `.apkg`.

`LocalCardStore.importAnkiE1` и `loadAnkiE1` работают с той же SQLite-БД
на GRDB, что и `load`/`save` ручных карточек. При первом открытии прежний
`cards.json` переносится транзакционно в `learning_snapshot` и остаётся
нетронутым как резервная копия. После миграции активен только `kanki.sqlite`.
Если прежний файл не читается, автоматический обмен приостанавливается;
подтверждённая ручная загрузка валидного снимка может запустить SQLite без
переноса legacy. В обоих случаях исходный файл остаётся на месте и не меняется.
Серверный JSON не меняется; обновление снимка не трогает таблицы импорта.
В #5 следует расширять эту БД, а не открывать второе хранилище.

Границы нотетайпа, Relations, идентичности и записи прогресса описаны
в [контракте v1](../docs/anki-exchange-v1.md). Здесь нет редактора заметок,
импорта в интерфейсе и обучения на импортированных картах.

В [итоговой проверке #150](https://github.com/EgorYolkin/kanki/pull/150#issuecomment-6975958134)
для входа прогресса использовали отдельно полученный `test2-gui.apkg`:
официальный планировщик Anki 26.09.3 создал два Good через backend, а
штатный диалог AnkiDesktop (Qt offscreen) экспортировал колоду с расписанием.
Адаптер прочитал этот экспорт с `--reviewed`, тест открыл продуктовую SQLite
повторно и сверил все импортированные значения и рёбра. Это не исходный
GUI-артефакт #146; данный прогон не повторял первичный GUI-импорт.

Из корня репозитория соберите синтетические входы и передайте их в тесты.
Загрузите отдельный пустой iPhone Simulator и задайте `KANKI_E1_SIMULATOR_ID`
его идентификатором из `xcrun simctl list devices booted`.

```bash
(
  set -euo pipefail
  unset KANKI_TEST_SERVER_URL KANKI_TEST_TOKEN
  unset TEST_RUNNER_KANKI_TEST_SERVER_URL TEST_RUNNER_KANKI_TEST_TOKEN
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  uv run --no-project --with genanki==0.13.1 python experiments/e1.py generate "$work"
  uv run --no-project --with anki==26.09.3 --with zstandard==0.25.0 \
    python experiments/e1_roundtrip.py "$work"
  for fixture in test1 test3 test4-type-change; do
    uv run --no-project --with zstandard==0.25.0 python experiments/e1_product_input.py \
      "$work/$fixture.apkg" "$work/$fixture.json"
  done
  uv run --no-project --with zstandard==0.25.0 python experiments/e1_product_input.py \
    --reviewed "$work/test2.apkg" "$work/test2.json"
  xcodegen generate
  mkdir -p build
  result="build/$(basename "$work").xcresult"
  TEST_RUNNER_KANKI_E1_INPUT_DIR="$work" xcodebuild test \
    -project Kanki.xcodeproj -scheme Kanki -configuration Debug \
    -destination "platform=iOS Simulator,id=${KANKI_E1_SIMULATOR_ID:?}" \
    -only-testing:KankiTests -derivedDataPath build/DerivedData \
    -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO
  python3 scripts/coverage_gate.py --bundle "$result"
)
```

`AnkiE1ImportTests` открывает настоящий `LocalCardStore` на временном пути.
В логе должны быть четыре строки `E1 package input:`; без переменной
окружения тот же тест использует встроенные синтетические входы. Ожидания
сверены с [GUI-отчётом #146](https://github.com/EgorYolkin/kanki/issues/3#issuecomment-6974240772):
две заметки и две карты, `requires` и `related` с обратными проекциями,
две записи Good, Learning с Unix due и `cards.ivl=0`, `revlog.ivl=-600`.
Команды выше создают свежий backend-экспорт Anki 26.09.3, не используют
удалённый артефакт GUI. Тест сверяет каждое исходное значение расписания и
revlog с повторно открытым файлом, а также неизменность байтов при повторе
и отказе, откат при конфликте прогресса и сохранность ручного FSRS-снимка.
