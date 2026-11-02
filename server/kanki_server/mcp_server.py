from __future__ import annotations

import os
from typing import Any

from mcp.server import MCPServer
from mcp.server.mcpserver.exceptions import ToolError

from .client import ApiError, KankiApi

mcp = MCPServer(
    "kanki",
    instructions=(
        "Read and write Kanki snapshots through the Kanki server. "
        "Always fetch the current revision before writing; a stale base_revision is rejected."
    ),
)


def _api() -> KankiApi:
    base_url = os.getenv("KANKI_SERVER_URL")
    token = os.getenv("KANKI_TOKEN")
    if not base_url or not token:
        raise ToolError("Set KANKI_SERVER_URL and KANKI_TOKEN in the MCP server environment")
    return KankiApi(base_url, token)


def _call(call: Any) -> dict[str, Any]:
    api = _api()
    try:
        return call(api)
    except ApiError as error:
        raise ToolError(f"Kanki API error {error.status_code}: {error.detail}") from error
    finally:
        api.close()


@mcp.tool()
def health() -> dict[str, Any]:
    """Check that the Kanki server is reachable and its database is healthy."""
    return _call(lambda api: api.health())


@mcp.tool()
def me() -> dict[str, Any]:
    """Return the token label and role used by this MCP server."""
    return _call(lambda api: api.me())


@mcp.tool()
def get_snapshot() -> dict[str, Any]:
    """Read the current Kanki snapshot and its revision.

    Returns revision 0 with null data when the server has no snapshot yet.
    """
    return _call(lambda api: api.get_snapshot())


@mcp.tool()
def put_snapshot(base_revision: int, data: dict[str, Any]) -> dict[str, Any]:
    """Replace the Kanki snapshot after checking base_revision.

    Fetch get_snapshot first and pass its revision. A stale revision is rejected
    with a conflict so two writers cannot silently overwrite each other.
    """
    return _call(lambda api: api.put_snapshot(base_revision=base_revision, data=data))


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
