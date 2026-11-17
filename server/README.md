# Kanki server

Сервер синхронизации Kanki: REST/JSON, ревизионные снимки и MCP-инструменты.
Канонический транспорт — HTTPS `kanki.host` (nginx + Let's Encrypt); uvicorn
слушает только `127.0.0.1`. SSH используется для установки и администрирования,
а не как канал данных. Tailnet-HTTP — legacy-режим, см. ниже.

## Что умеет

- `GET /v1/health` — жив ли сервер и БД, без токена.
- `GET /v1/me` — метка и роль токена.
- `GET /v1/snapshot` — текущий снимок и `revision`; `data: null`, если данных нет.
- `PUT /v1/snapshot` — запись снимка с `base_revision`; устаревшая ревизия даёт
  `409 current_revision`, без автоматического мержа.
- `POST/GET/DELETE /v1/tokens` — персональные токены устройства и агентов
  (только admin-токен).
- MCP (stdio): `health`, `me`, `get_snapshot`, `put_snapshot`.

Снимок — непрозрачный JSON-объект до 10 МиБ. `schema_version: 1` предварительная:
контракт Anki и Э1 ещё не заморожены.

## Локальный запуск

Нужны Python 3.12+ и [uv](https://docs.astral.sh/uv/).

```bash
cd server
export KANKI_ADMIN_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
export KANKI_DATABASE="$PWD/data/kanki.sqlite3"
uv sync --group dev
uv run uvicorn kanki_server.app:app --host 127.0.0.1 --port 8000
```

Проверка и выдача токена устройству:

```bash
curl -s http://127.0.0.1:8000/v1/health
curl -s -X POST http://127.0.0.1:8000/v1/tokens \
  -H "Authorization: Bearer $KANKI_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"label":"iphone"}'
```

В приложении: «Настройки» → «Сервер» → `http://127.0.0.1:8000`, токен из ответа,
«Проверить соединение». В симуляторе localhost указывает на Mac.

## Публичный HTTPS (канонический)

Конфигурация — из `docs/server-protocol.md`: uvicorn слушает `127.0.0.1:8000`,
наружу API отдаёт nginx с сертификатом Let's Encrypt (`kanki.host`),
`/docs`, `/redoc`, `/openapi.json` и `/v1/tokens` закрыты извне, действуют
`limit_req` и лимит тела. Порт 8000 в интернет не публикуется.

1. Разверните сервис на loopback: `python3 scripts/deploy_server.py --ssh user@server-ip`.
2. Настройте vhost `/etc/nginx/sites-enabled/kanki` и snippets по
   `docs/server-protocol.md`; проверьте `nginx -t && systemctl reload nginx`.
3. В приложении укажите `https://kanki.host` и выданный device-токен.

## Tailnet HTTP (legacy)

Режим без TLS-терминации: сервер слушает `0.0.0.0:8000` и доступен только
внутри tailnet. Он не даёт закрытия служебных маршрутов, `limit_req` и HSTS
из протокола — включайте только как осознанное исключение.

1. Установите Tailscale на сервер, Mac и iPhone, войдите в один tailnet.
2. В юните замените `--host 127.0.0.1` на `--host 0.0.0.0` и перезапустите сервис.
3. Закройте порт для всех интерфейсов, кроме `tailscale0`:

   ```bash
   sudo ufw allow in on tailscale0 to any port 8000 proto tcp
   sudo ufw deny 8000/tcp
   ```

4. В приложении укажите `http://100.x.y.z:8000`. ATS разрешает IP через
   `NSAllowsLocalNetworking`; снаружи tailnet адрес недоступен.

HTTP не шифруется на уровне приложения: конфиденциальность даёт WireGuard,
которым управляет Tailscale. Не публикуйте порт в интернет и не включайте
Funnel без HTTPS-терминации.

## Деплой по SSH

С Mac, где лежит репозиторий:

```bash
python3 scripts/deploy_server.py --ssh user@server-ip --dry-run
python3 scripts/deploy_server.py --ssh user@server-ip
```

Скрипт копирует `server/` через `rsync`, создаёт `.env` с admin-токеном,
устанавливает systemd user-юнит `kanki-server` на `127.0.0.1`, запускает его,
ждёт `/v1/health` и выпускает токен для `iphone`. Наружу сервис открывает
только nginx по `docs/server-protocol.md`; при деплое печатается
`--public-url` (по умолчанию `https://kanki.host`).
Требования на сервере: `ssh`, `rsync`, `uv`, `systemd`; nginx и сертификат —
по протоколу.

Если `uv` не установлен:

```bash
ssh user@server-ip 'curl -LsSf https://astral.sh/uv/install.sh | sh'
```

Admin-токен не печатается. Он лежит в `~/kanki-server/.env` с правами `0600`;
храните его как пароль и не коммитьте.

## MCP для агентов

MCP-сервер работает по stdio и вызывает тот же REST API:

```bash
export KANKI_SERVER_URL="http://100.x.y.z:8000"
export KANKI_TOKEN="<device-token>"
uv run --project server kanki-mcp
```

Пример конфигурации клиента (пути и токен подставьте свои):

```json
{
  "mcpServers": {
    "kanki": {
      "command": "/path/to/uv",
      "args": ["run", "--project", "/path/to/kanki/server", "kanki-mcp"],
      "env": {
        "KANKI_SERVER_URL": "http://100.x.y.z:8000",
        "KANKI_TOKEN": "<device-token>"
      }
    }
  }
}
```

Инструменты возвращают структурированный JSON. `put_snapshot` требует
`base_revision` из `get_snapshot`; при `409` агент должен перечитать снимок,
а не повторять запись вслепую.

## Тесты

```bash
uv sync --project server --group dev
uv run --project server pytest
```

Проверяются авторизация, ревизии, `409`, лимит размера, отзыв токена, WAL,
персистентность и MCP-инструменты через in-memory MCP client.
