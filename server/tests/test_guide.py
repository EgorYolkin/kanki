import re
from collections.abc import Iterator
from http import HTTPMethod
from importlib import resources
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from kanki_server.app import create_app


@pytest.fixture
def client(tmp_path: Path) -> Iterator[TestClient]:
    app = create_app(database_path=tmp_path / "kanki.sqlite3", admin_token=None)
    with TestClient(app, follow_redirects=False) as test_client:
        yield test_client


def test_public_guide_serves_packaged_markdown(client: TestClient) -> None:
    response = client.get("/v1/guide.md")

    assert response.status_code == 200
    assert response.headers["Content-Type"] == "text/markdown; charset=utf-8"
    assert response.headers["Cache-Control"] == "no-store"
    assert response.content.decode("utf-8").splitlines()[0] == "# Kanki API"
    guide = resources.files("kanki_server").joinpath("guide.md")
    assert response.content == guide.read_bytes()


def test_documented_routes_match_openapi(client: TestClient) -> None:
    paths = client.get("/openapi.json").json()["paths"]
    content = paths["/v1/guide.md"]["get"]["responses"]["200"]["content"]
    assert set(content) == {"text/markdown"}

    routes = {
        f"{method.upper()} {path}"
        for path, item in paths.items() if path.startswith("/v1/")
        for method in item if method.upper() in HTTPMethod
    }
    guide = client.get("/v1/guide.md").text
    documented = set(re.findall(r"`([A-Z]+ /v1/[^`\s]+)`", guide))
    assert documented == routes
