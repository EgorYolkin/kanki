from __future__ import annotations

from typing import Any

import pytest
from mcp import Client

from kanki_server import mcp_server
from kanki_server.client import ApiError


class FakeApi:
    def __init__(self) -> None:
        self.put_calls: list[tuple[int, dict[str, Any]]] = []
        self.fail = False

    def close(self) -> None:
        pass

    def _check(self) -> None:
        if self.fail:
            raise ApiError(401, {"code": "invalid_token"})

    def health(self) -> dict[str, Any]:
        self._check()
        return {"status": "ok", "version": "test", "time": "now"}

    def me(self) -> dict[str, Any]:
        self._check()
        return {"label": "agent", "role": "device"}

    def get_snapshot(self) -> dict[str, Any]:
        self._check()
        return {
            "revision": 3,
            "schema_version": 1,
            "data": {"cards": []},
            "updated_at": "now",
        }

    def put_snapshot(self, *, base_revision: int, data: dict[str, Any], schema_version: int = 1):
        del schema_version
        self._check()
        self.put_calls.append((base_revision, data))
        return {
            "revision": base_revision + 1,
            "schema_version": 1,
            "data": data,
            "updated_at": "now",
        }


@pytest.fixture
def fake_api(monkeypatch: pytest.MonkeyPatch) -> FakeApi:
    fake = FakeApi()
    monkeypatch.setattr(mcp_server, "_api", lambda: fake)
    return fake


async def test_tools_read_and_write_snapshot(fake_api: FakeApi) -> None:
    async with Client(mcp_server.mcp) as client:
        tools = await client.list_tools()
        assert {"health", "me", "get_snapshot", "put_snapshot"} <= {
            tool.name for tool in tools.tools
        }

        health = await client.call_tool("health", {})
        assert health.structured_content == {
            "status": "ok",
            "version": "test",
            "time": "now",
        }

        snapshot = await client.call_tool("get_snapshot", {})
        assert snapshot.structured_content["revision"] == 3

        written = await client.call_tool(
            "put_snapshot",
            {"base_revision": 3, "data": {"cards": [{"id": "a"}]}},
        )
        assert written.structured_content["revision"] == 4
        assert fake_api.put_calls == [(3, {"cards": [{"id": "a"}]})]


async def test_tool_errors_are_surfaced(fake_api: FakeApi) -> None:
    fake_api.fail = True

    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("health", {})

    assert result.is_error is True
    assert result.content[0].type == "text"
    assert "401" in result.content[0].text
