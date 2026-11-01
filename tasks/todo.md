# Этапы Kanki — [GitHub Issues](https://github.com/EgorYolkin/kanki/issues)

- [x] Инфраструктура качества ([#50](https://github.com/EgorYolkin/kanki/issues/50)) — доменная логика вынесена в `Kanki/Domain` (24 unit-теста, покрытие 100 % строк при пороге 95 %, `scripts/coverage_gate.py`), экраны — в `Kanki/Views`; SwiftLint `--strict` и markdownlint проходят без нарушений; CI из трёх заданий; правила по каталогам и `docs/quality-gates.md`. Проверено локально: `./scripts/ci.sh` вернул 0, четыре UI-теста прошли на iPhone 17e (Xcode 27.2). Поведение приложения не изменилось.
- [x] 1. [Скелет iOS (#2)](https://github.com/EgorYolkin/kanki/issues/2) — сборка и запуск на iPhone 17e (iOS 26.3.1) выполнены; четыре UI-теста проверили вкладки, переходы, пустые состояния, пробные карточки, оценку ответа, очередь повторения с итогом ([#30](https://github.com/EgorYolkin/kanki/issues/30)) и страницу настроек с сохранением темы ([#32](https://github.com/EgorYolkin/kanki/issues/32)). Карточки, оценки и сеанс живут только в памяти и исчезают после перезапуска; сохраняется только выбранная тема; SRS, сервера и синхронизации нет.
- [ ] 2. [Контракт и Э1 (#3)](https://github.com/EgorYolkin/kanki/issues/3) — автоматический round-trip на backend Anki 26.09.3 прошёл: импорт, Good, экспорт с revlog, обновление без дублей/потери прогресса, конфликт типа. Визуальный прогон AnkiDesktop и обратный конвертер в БД Kanki не проверены; нотетайп/контракт не заморожены. Зависимости: нет.
- [ ] 3. [Публикация и обмен (#4)](https://github.com/EgorYolkin/kanki/issues/4) — публикация двух заметок и идемпотентный экспорт .apkg; проверить повторную публикацию и импорт. Зависимости: этап 2.
- [ ] 4. [Локальный цикл (#5)](https://github.com/EgorYolkin/kanki/issues/5) — импорт → WKWebView → FSRS → сохранённый review; проверить перезапуск. Зависимости: этапы 2, 3.

- [ ] Контроль: локальный учебный цикл работает офлайн.
- [ ] 5. [Граф и поиск (#6)](https://github.com/EgorYolkin/kanki/issues/6) — backlinks, FTS5, Canvas; проверить переходы и висячие связи. Зависимости: этап 4.
- [ ] 6. [Повторение и правки (#7)](https://github.com/EgorYolkin/kanki/issues/7) — Cram, requires, редактор и защита правок; проверить due и конфликт публикации. Зависимости: этапы 4, 5.
- [ ] 7. [Sync и Anki (#8)](https://github.com/EgorYolkin/kanki/issues/8) — pull/push, Keychain/TLS, Э3/Э4/Э6; проверить офлайн-повтор и мерж по (guid, ord). Зависимости: этапы 3, 4.
- [ ] Контроль: сверить AnkiMobile custom sync URL до обещания общего прогресса.
- [ ] 8. [Эксплуатация (#9)](https://github.com/EgorYolkin/kanki/issues/9) — конфликты, мержи, APNs, бэкапы и restore, Э2/Э5; проверить восстановленный .apkg. Зависимости: этапы 5–7.
