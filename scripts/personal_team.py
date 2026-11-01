#!/usr/bin/env python3
"""Build and reinstall Kanki on one personal iOS device using local Xcode signing."""

import argparse
import datetime as dt
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LABEL = "app.kanki.personal-team-refresh"
INTERVAL = dt.timedelta(days=5)
STATE = Path.home() / "Library/Application Support/Kanki/PersonalTeam"
LOGS = Path.home() / "Library/Logs/Kanki"
AGENT = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
UDID_RE = re.compile(r"[A-Fa-f0-9-]{16,64}\Z")
BUNDLE_RE = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=capture)
    return result.stdout if capture else ""


def check_device(udid: str) -> None:
    devices = json.loads(run("xcrun", "devicectl", "list", "devices", "--json-output", "-", capture=True))["result"]["devices"]
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        if hardware.get("udid", "").upper() != udid.upper():
            continue
        if hardware.get("platform") != "iOS" or device.get("properties", {}).get("state", {}).get("visibilityClass") == "simulators":
            raise ValueError("Указан не физический iPhone/iPad")
        connection = device.get("properties", {}).get("connection", {}).get("state")
        if not connection or connection == "unavailable":
            raise ValueError("Устройство недоступно: подключите его по USB или настройте сопряжение по Wi-Fi")
        return
    raise ValueError("Устройство с указанным UDID не найдено в devicectl")


def last_success(team: str, udid: str, bundle: str) -> Path:
    return STATE / f"{team}-{udid.upper()}-{bundle}.json"


def signed_profile(app: Path, team: str, udid: str, bundle: str) -> None:
    run("codesign", "--verify", "--deep", "--strict", str(app))
    profile = app / "embedded.mobileprovision"
    if not profile.is_file():
        raise ValueError("В собранном приложении нет provisioning profile")
    details = plistlib.loads(subprocess.run(
        ("security", "cms", "-D", "-i", str(profile)), check=True, capture_output=True,
    ).stdout)
    if team not in details.get("TeamIdentifier", []):
        raise ValueError("Provisioning profile принадлежит другой команде")
    if udid.upper() not in {item.upper() for item in details.get("ProvisionedDevices", [])}:
        raise ValueError("Устройство не включено в provisioning profile")
    app_id = details.get("Entitlements", {}).get("application-identifier", "")
    if app_id != f"{team}.{bundle}":
        raise ValueError("App ID в provisioning profile не совпадает с выбранным bundle ID")
    if details["ExpirationDate"].replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1):
        raise ValueError("Профиль истекает менее чем через сутки")


def refresh(args: argparse.Namespace) -> None:
    stamp = last_success(args.team, args.device, args.bundle)
    if not args.force and stamp.exists():
        try:
            previous = dt.datetime.fromisoformat(json.loads(stamp.read_text())["installed_at"])
            elapsed = dt.datetime.now(dt.timezone.utc) - previous
            if dt.timedelta() <= elapsed < INTERVAL:
                print("Переподпись пока не нужна; для немедленной установки используйте --force")
                return
        except (TypeError, ValueError, KeyError, json.JSONDecodeError):
            pass  # Damaged state must trigger a real attempt, not a false success.

    check_device(args.device)
    derived = STATE / "DerivedData"
    run(
        "xcodebuild", "-project", str(ROOT / "Kanki.xcodeproj"), "-scheme", "Kanki",
        "-configuration", "Debug", "-destination", f"platform=iOS,id={args.device}",
        "-derivedDataPath", str(derived), "-allowProvisioningUpdates",
        "-allowProvisioningDeviceRegistration", f"DEVELOPMENT_TEAM={args.team}",
        f"PRODUCT_BUNDLE_IDENTIFIER={args.bundle}", "CODE_SIGN_STYLE=Automatic", "CODE_SIGNING_ALLOWED=YES", "build",
    )
    app = derived / "Build/Products/Debug-iphoneos/Kanki.app"
    if not app.is_dir():
        raise ValueError("Сборка завершилась без Kanki.app")
    signed_profile(app, args.team, args.device, args.bundle)
    run("xcrun", "devicectl", "device", "install", "app", "--device", args.device, str(app))
    stamp.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=stamp.parent, delete=False) as output:
        json.dump({"installed_at": dt.datetime.now(dt.timezone.utc).isoformat()}, output)
        temporary = Path(output.name)
    temporary.replace(stamp)
    print("Kanki установлен; следующая попытка через 5 дней или по --force")


def agent_config(args: argparse.Namespace) -> dict:
    return {
        "Label": LABEL,
        "ProgramArguments": [
            "/usr/bin/python3", str(Path(__file__).resolve()), "refresh",
            "--team-id", args.team, "--device-id", args.device, "--bundle-id", args.bundle,
        ],
        "RunAtLoad": True,
        "StartCalendarInterval": {"Hour": 9, "Minute": 0},
        "Umask": 0o077,
        "WorkingDirectory": str(ROOT),
        "StandardOutPath": str(LOGS / "personal-team.log"),
        "StandardErrorPath": str(LOGS / "personal-team-error.log"),
    }


def install_agent(args: argparse.Namespace) -> None:
    if AGENT.exists():
        raise ValueError(f"LaunchAgent уже установлен: {AGENT}; сначала выполните uninstall-agent")
    LOGS.mkdir(parents=True, exist_ok=True)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=AGENT.parent, delete=False) as output:
        plistlib.dump(agent_config(args), output)
        temporary = Path(output.name)
    temporary.replace(AGENT)
    try:
        run("launchctl", "bootstrap", f"gui/{os.getuid()}", str(AGENT))
    except subprocess.CalledProcessError:
        AGENT.unlink()
        raise
    print(f"LaunchAgent установлен: {AGENT}. Первая попытка запускается при загрузке; логи: {LOGS}")


def uninstall_agent() -> None:
    if not AGENT.exists():
        print("LaunchAgent не установлен")
        return
    run("launchctl", "bootout", f"gui/{os.getuid()}", str(AGENT))
    AGENT.unlink()
    print("LaunchAgent удалён; приложение и данные на устройстве не затронуты")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("refresh", "install-agent"):
        sub = commands.add_parser(command)
        sub.add_argument("--team-id", dest="team", required=True)
        sub.add_argument("--device-id", dest="device", required=True)
        sub.add_argument("--bundle-id", dest="bundle", required=True)
        if command == "refresh":
            sub.add_argument("--force", action="store_true", help="пересобрать и установить даже до истечения 5 дней")
    commands.add_parser("uninstall-agent")
    args = parser.parse_args()
    try:
        if args.command != "uninstall-agent":
            if not TEAM_RE.fullmatch(args.team) or not UDID_RE.fullmatch(args.device) or not BUNDLE_RE.fullmatch(args.bundle):
                raise ValueError("Укажите корректные Team ID (10 символов), физический UDID и bundle ID")
        if args.command == "refresh":
            refresh(args)
        elif args.command == "install-agent":
            install_agent(args)
        else:
            uninstall_agent()
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError, plistlib.InvalidFileException) as error:
        print(f"Переподпись не завершена: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
