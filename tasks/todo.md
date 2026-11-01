# Этапы Kanki — [GitHub Issues](https://github.com/EgorYolkin/kanki/issues)

- [x] 1. [Скелет iOS (#2)](https://github.com/EgorYolkin/kanki/issues/2) — сборка и запуск на iPhone 17e (iOS 26.3.1) выполнены; UI-тесты проверили вкладки, переходы, пробные карточки и оценку ответа. Карточки и оценки живут только в сеансе: после перезапуска исчезают; SRS и синхронизации нет.
- [ ] 2. [Контракт и Э1 (#3)](https://github.com/EgorYolkin/kanki/issues/3) — UID/GUID/Relations и AnkiDesktop round-trip без дублей/потери прогресса; проверить Э1. Зависимости: нет.
- [ ] 3. [Публикация и обмен (#4)](https://github.com/EgorYolkin/kanki/issues/4) — публикация двух заметок и идемпотентный экспорт .apkg; проверить повторную публикацию и импорт. Зависимости: этап 2.
- [ ] 4. [Локальный цикл (#5)](https://github.com/EgorYolkin/kanki/issues/5) — импорт → WKWebView → FSRS → сохранённый review; проверить перезапуск. Зависимости: этапы 2, 3.

- [ ] Контроль: локальный учебный цикл работает офлайн.
- [ ] 5. [Граф и поиск (#6)](https://github.com/EgorYolkin/kanki/issues/6) — backlinks, FTS5, Canvas; проверить переходы и висячие связи. Зависимости: этап 4.
- [ ] 6. [Повторение и правки (#7)](https://github.com/EgorYolkin/kanki/issues/7) — Cram, requires, редактор и защита правок; проверить due и конфликт публикации. Зависимости: этапы 4, 5.
- [ ] 7. [Sync и Anki (#8)](https://github.com/EgorYolkin/kanki/issues/8) — pull/push, Keychain/TLS, Э3/Э4/Э6; проверить офлайн-повтор и мерж по (guid, ord). Зависимости: этапы 3, 4.
- [ ] Контроль: сверить AnkiMobile custom sync URL до обещания общего прогресса.
- [ ] 8. [Эксплуатация (#9)](https://github.com/EgorYolkin/kanki/issues/9) — конфликты, мержи, APNs, бэкапы и restore, Э2/Э5; проверить восстановленный .apkg. Зависимости: этапы 5–7.
