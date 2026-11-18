"""
Serve the real Kanki app with synthetic data and two controllable ACK failures.
"""

import os
from pathlib import Path

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

from kanki_server.app import create_app
from kanki_server.publication import PublishedNote

TOKEN = "stage8-synthetic-token"
UID = "n-018f3a2b-7c41-7000-8000-000000000001"
app = create_app(database_path=Path(os.environ["KANKI_DELTA_FIXTURE_DB"]), admin_token=TOKEN)
mode = "online"


@app.post("/fixture/{command}")
def fixture(command: str, request: Request):
    if request.headers.get("authorization") != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401)

    global mode
    if command in {"seed", "update"}:
        app.state.database.publish([PublishedNote(
            uid=UID, schema_version=1, kind="fact",
            title="Синтетика: дельта 1" if command == "seed" else "Синтетика: дельта 2",
            question="Синтетический вопрос", answer="Синтетический ответ",
            body="Тестовое содержимое", sources=[], relations=[],
        )])
    elif command in {"offline", "lose-ack"}:
        mode = command
    else:
        raise HTTPException(status_code=404)

    return {"ok": True}


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
