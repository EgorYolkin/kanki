from __future__ import annotations

from typing import Any

import httpx


class ApiError(Exception):
    def __init__(self, status_code: int, detail: Any) -> None:
        super().__init__(f"Kanki API returned {status_code}: {detail}")
        self.status_code = status_code
        self.detail = detail


class KankiApi:
    def __init__(
        self,
        base_url: str,
        token: str,
        *,
        client: httpx.Client | None = None,
    ) -> None:
        self._owns_client = client is None
        self._client = client or httpx.Client(
            base_url=base_url.rstrip("/"),
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def _request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        response = self._client.request(method, path, **kwargs)
        if response.is_success:
            return response.json()
        try:
            detail = response.json()
        except ValueError:
            detail = response.text
        raise ApiError(response.status_code, detail)

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/v1/health")

    def me(self) -> dict[str, Any]:
        return self._request("GET", "/v1/me")

    def get_snapshot(self) -> dict[str, Any]:
        return self._request("GET", "/v1/snapshot")

    def put_snapshot(
        self,
        *,
        base_revision: int,
        data: dict[str, Any],
        schema_version: int = 1,
    ) -> dict[str, Any]:
        return self._request(
            "PUT",
            "/v1/snapshot",
            json={
                "schema_version": schema_version,
                "base_revision": base_revision,
                "data": data,
            },
        )
