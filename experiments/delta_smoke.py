"""
Serve the real Kanki app with synthetic data and two controllable ACK failures.
"""

import os
from pathlib import Path

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

from kanki_server.app import create_app, hash_token
from kanki_server.publication import PublishedNote

TOKEN = "stage8-synthetic-token"
DEVICE_TOKEN = "stage8-synthetic-device-token"
ROTATED_TOKEN = "stage8-synthetic-rotated-token"
DEVICE_ID = "c468658f-cf36-4677-a169-767cee148e2f"
ROTATED_ID = "080a1028-c95b-4195-bc55-8c687d66cadd"
UID = "n-018f3a2b-7c41-7000-8000-000000000001"
app = create_app(database_path=Path(os.environ["KANKI_DELTA_FIXTURE_DB"]), admin_token=TOKEN)
mode = "online"


@app.post("/fixture/{command}")
def fixture(command: str, request: Request):
    if request.headers.get("authorization") != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401)

    global mode
    titles = {
        "seed": "Синтетика: дельта 1",
        "update": "Синтетика: дельта 2",
        "update-again": "Синтетика: дельта 3",
    }
    database = app.state.database
    if command in titles:
        database.publish([
            PublishedNote(
                uid=UID,
                schema_version=1,
                kind="fact",
                title=titles[command],
                question="Синтетический вопрос",
                answer="Синтетический ответ",
                body="Тестовое содержимое",
                sources=[],
                relations=[],
            ),
        ])
        if command == "seed":
            add_device_token(token_id=DEVICE_ID, token=DEVICE_TOKEN)
        elif command == "update-again":
            database.revoke_token(DEVICE_ID)
            add_device_token(token_id=ROTATED_ID, token=ROTATED_TOKEN)
    elif command in {"offline", "lose-ack"}:
        mode = command
    else:
        raise HTTPException(status_code=404)

    return {"ok": True}


def add_device_token(*, token_id: str, token: str) -> None:
    app.state.database.create_token(
        token_id=token_id,
        label="Synthetic UI device",
        token_hash=hash_token(token),
        created_at="2026-01-01T00:00:00Z",
    )


@app.middleware("http")
async def simulate_offline_and_lost_ack(request: Request, call_next):
    global mode
    if request.url.path != "/v1/changes":
        return await call_next(request)
    if mode == "offline":
        return JSONResponse({"detail": "synthetic offline"}, status_code=503)

    response = await call_next(request)
    if mode == "lose-ack" and request.method == "POST" and response.status_code == 200:
        mode = "online"
        # call_next has received the response headers; the DB transaction already committed.
        return JSONResponse({"detail": "synthetic lost acknowledgement"}, status_code=503)

    return response
