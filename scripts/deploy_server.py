#!/usr/bin/env python3
"""Deploy the Kanki server over SSH into a systemd user service.

Canonical posture (docs/server-protocol.md): uvicorn listens on loopback only
and nginx terminates TLS for the public domain. SSH is used for installation,
logs and token issuance, never as the app data channel.
"""

from __future__ import annotations

import argparse
import json
import re
import secrets
import shlex
import subprocess
import sys
import time
from pathlib import Path

SSH_TARGET = re.compile(r"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$")
UNIT_NAME = "kanki-server.service"


def run(command: list[str], *, input_text: str | None = None, dry_run: bool) -> str:
    print("+", " ".join(shlex.quote(part) for part in command))
    if dry_run:
        return ""
    result = subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(f"command failed with {result.returncode}")
    return result.stdout.strip()


def ssh(target: str, command: str, *, input_text: str | None = None, dry_run: bool) -> str:
    return run(["ssh", target, command], input_text=input_text, dry_run=dry_run)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh", required=True, help="user@host or user@tailscale-ip")
    parser.add_argument("--remote-dir", default="kanki-server", help="directory in the remote home")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--public-url",
        default="https://kanki.host",
        help="HTTPS address served by nginx in front of uvicorn",
    )
    parser.add_argument("--label", default="iphone", help="label for the first device token")
    parser.add_argument("--admin-token", default=None, help="reuse an existing admin token")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not SSH_TARGET.match(args.ssh):
        raise SystemExit("--ssh must look like user@host or user@100.x.y.z")
    if "/" in args.remote_dir or args.remote_dir.startswith("."):
        raise SystemExit("--remote-dir must be a simple directory name in the remote home")

    repo_root = Path(__file__).resolve().parents[1]
    server_dir = repo_root / "server"
    remote = f"$HOME/{args.remote_dir}"
    admin_token = args.admin_token or secrets.token_urlsafe(32)

    dry_run = args.dry_run
    remote_home = ssh(args.ssh, 'printf %s "$HOME"', dry_run=dry_run) or "$HOME"
    remote_absolute = f"{remote_home}/{args.remote_dir}"
    ssh(args.ssh, f"mkdir -p {remote}/data", dry_run=dry_run)
    run(
        [
            "rsync",
            "-az",
            "--delete",
            "--exclude",
            ".venv",
            "--exclude",
            "data",
            "--exclude",
            "__pycache__",
            "--exclude",
            ".env",
            f"{server_dir}/",
            f"{args.ssh}:{args.remote_dir}/",
        ],
        dry_run=dry_run,
    )

    env_file = "\n".join(
        [
            f"KANKI_ADMIN_TOKEN={admin_token}",
            f"KANKI_DATABASE={remote_absolute}/data/kanki.sqlite3",
            f"KANKI_MAX_SNAPSHOT_BYTES={10 * 1024 * 1024}",
            "",
        ]
    )
    ssh(
        args.ssh,
        f"umask 077; cat > {remote}/.env",
        input_text=env_file,
        dry_run=dry_run,
    )

    uv_path = ssh(args.ssh, "command -v uv", dry_run=dry_run)
    if not dry_run and not uv_path:
        raise SystemExit(
            "uv is not installed on the server: "
            "ssh ... 'curl -LsSf https://astral.sh/uv/install.sh | sh'"
        )
    uv_path = uv_path or "/usr/local/bin/uv"

    unit = f"""[Unit]
Description=Kanki sync server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/{args.remote_dir}
EnvironmentFile=%h/{args.remote_dir}/.env
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart={uv_path} run --project %h/{args.remote_dir} uvicorn kanki_server.app:app --host 127.0.0.1 --port {args.port}
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=default.target
"""
    ssh(
        args.ssh,
        "mkdir -p $HOME/.config/systemd/user && "
        f"cat > $HOME/.config/systemd/user/{UNIT_NAME}",
        input_text=unit,
        dry_run=dry_run,
    )
    ssh(
        args.ssh,
        f"cd {remote} && {shlex.quote(uv_path)} sync --project {remote}",
        dry_run=dry_run,
    )
    ssh(
        args.ssh,
        f"systemctl --user daemon-reload && systemctl --user enable --now {UNIT_NAME} "
        f"&& loginctl enable-linger $USER",
        dry_run=dry_run,
    )

    if dry_run:
        print(f"dry-run: would deploy to {args.ssh}:{args.remote_dir}, port {args.port}")
        return

    health = ""
    for _ in range(15):
        try:
            health = ssh(
                args.ssh,
                f"curl -fsS http://127.0.0.1:{args.port}/v1/health",
                dry_run=False,
            )
            if health:
                break
        except SystemExit:
            time.sleep(1)
    if not health:
        raise SystemExit("server did not become healthy; check: systemctl --user status kanki-server")

    token_json = ssh(
        args.ssh,
        (
            f"curl -fsS -X POST http://127.0.0.1:{args.port}/v1/tokens "
            f"-H {shlex.quote(f'Authorization: Bearer {admin_token}')} "
            "-H 'Content-Type: application/json' "
            f"-d {shlex.quote(json.dumps({'label': args.label}))}"
        ),
        dry_run=False,
    )
    token = json.loads(token_json)["token"]

    print()
    print("Kanki server is running on loopback; nginx must terminate TLS.")
    print(f"URL:   {args.public_url}")
    print(f"Token: {token}  (device label: {args.label})")
    print("Admin token: ~/kanki-server/.env (not printed)")
    print("nginx vhost and certificate: docs/server-protocol.md")


if __name__ == "__main__":
    main()
