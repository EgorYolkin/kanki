# Серверный протокол Kanki

Решение для первого серверного среза: приложение и агенты ходят в один
REST/JSON API внутри Tailscale; SSH используется только для установки и ops.

## Выбор

| Слой | Решение | Причина |
| --- | --- | --- |
| Транспорт | HTTP внутри Tailscale/WireGuard | IP без домена и сертификатов; шифрование сети |
| API | REST + JSON, `/v1`, OpenAPI 3.1 | `URLSession`, curl, отладка, агенты |
| Аутентификация | `Authorization: Bearer` | отдельные токены устройства/агентов, отзыв |
| Хранение | SQLite WAL, `busy_timeout`, `synchronous=NORMAL` | один писатель, конкурентные чтения |
| Обмен | снимок + `revision`/`base_revision`, `409` | без ложного мержа и потери чужих правок |
| Агенты | OpenAPI + MCP stdio | один API, два способа доступа |
| SSH | rsync + systemd user service | деплой и диагностика, не канал данных iOS |

Почему не gRPC: Swift-клиент и агенты получают лишний тулчейн, а выигрыш для
одного пользователя и редких снимков не оправдан. Почему не SSH из приложения:
iOS-приложению пришлось бы хранить SSH-ключи и реализовывать SSH-клиент; для
данных это не нужно.

## Контракт `/v1`

- `GET /v1/health` — без токена: `{status, version, time}`.
- `GET /v1/me` — `{label, role}` для проверки токена.
- `GET /v1/snapshot` — `{revision, schema_version, data, updated_at}`;
  при отсутствии данных `revision = 0`, `data = null`.
- `PUT /v1/snapshot` — `{schema_version, base_revision, data}`.
  Успех возвращает новую ревизию; несовпадение `base_revision` — `409` с
  `detail.current_revision`. Запись атомарная, лимит 10 МиБ.
- `POST /v1/tokens` `{label}` → `{id, label, token}`; plaintext один раз.
- `GET /v1/tokens`, `DELETE /v1/tokens/{id}` — только admin.

Токены: bootstrap admin из `KANKI_ADMIN_TOKEN`; остальные — случайные 32 байта,
в БД только SHA-256. Сравнение admin-токена — `hmac.compare_digest`.

## Снимок и ревизии

`data` — JSON-объект текущего `LearningSnapshot` (карточки, оценки, в будущем
расписание). Сервер не интерпретирует поля и не мержит их. Клиент обязан
перечитать `revision` перед записью; при `409` показывается конфликт, а не
повторная запись вслепую. Delta-обмен, tombstones и мерж `(guid, ord)` —
этап 07, не этот контракт.

`schema_version: 1` предварительная: Э1 (#3) ещё не заморозил схему Anki.

## Безопасность и Tailscale

- Сервер слушает `0.0.0.0:8000`, но firewall разрешает порт только на
  `tailscale0`; в интернет порт не публикуется.
- HTTP внутри tailnet не заменяет TLS на уровне приложения; транспорт
  шифрует WireGuard. Funnel/публичный доступ без HTTPS-терминации запрещён.
- iOS ATS: `NSAllowsLocalNetworking` разрешает IP и `.local`, не открывая
  произвольный HTTP в интернет.
- Токен на подписанной сборке — Keychain; в неподписанном симуляторе без
  entitlement используется файл в sandbox с file protection и правами `0600`.
- `.env`, токены и база не коммитятся.

## Доступ агентов

- REST: `curl`/OpenAPI `/docs` с токеном агента.
- MCP: `uv run --project server kanki-mcp` по stdio; инструменты `health`,
  `me`, `get_snapshot`, `put_snapshot`. Агент обязан передавать `base_revision`
  из последнего `get_snapshot`.
- SSH: деплой, `journalctl --user -u kanki-server`, выдача/отзыв токенов.

## Границы

- Нет автоматической фоновой синхронизации и мержа.
- Нет многопользовательского доступа и прав на отдельные карточки.
- Нет delta/`changes?since=` и привязки к Anki `(guid, ord)`.
- Нет TLS-терминации и pinning; это этап 07.

Инструкции по запуску, деплою и MCP — в [server/README.md](../server/README.md).
