#!/usr/bin/env python3
"""Порог покрытия доменного слоя по результату `xcodebuild test`.

Считает только файлы внутри `--scope` (по умолчанию `Kanki/Domain`).
SwiftUI-представления проверяются XCUITest и намеренно не входят в порог:
см. docs/quality-gates.md.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

DEFAULT_SCOPE = "Kanki/Domain"
DEFAULT_THRESHOLD = 95.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", default="build/Test.xcresult", help="путь к .xcresult")
    parser.add_argument("--scope", default=DEFAULT_SCOPE, help="каталог, для которого действует порог")
    parser.add_argument(
        "--project",
        default="Kanki.xcodeproj/project.pbxproj",
        help="сгенерированный проект для сверки состава файлов",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=float(os.environ.get("COVERAGE_THRESHOLD", DEFAULT_THRESHOLD)),
        help="минимальный процент (или переменная COVERAGE_THRESHOLD)",
    )
    return parser.parse_args()


def load_report(bundle: Path) -> dict:
    if not bundle.exists():
        sys.exit(f"Нет результата тестов: {bundle}. Сначала запустите scripts/test.sh.")
    result = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(bundle)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        sys.exit(f"xccov не прочитал {bundle}:\n{result.stderr.strip()}")
    return json.loads(result.stdout)


def percent(covered: int, executable: int) -> float:
    return 100.0 * covered / executable if executable else 0.0


def collect(report: dict, scope: str) -> tuple[list[dict], dict | None]:
    needle = f"/{scope.strip('/')}/"
    files: list[dict] = []
    seen: set[str] = set()
    app_target: dict | None = None
    for target in report.get("targets", []):
        if target.get("name", "").endswith(".app"):
            app_target = target
        for file in target.get("files", []):
            path = file.get("path", "").replace("\\", "/")
            if needle in path and path not in seen:
                seen.add(path)
                files.append(file)
    return files, app_target


def files_missing_from_project(scope: str, project: Path) -> list[str]:
    """Файлы каталога, которых нет в сгенерированном проекте.

    Ловит случай, когда новый файл домена не попал в проект (забыли
    `xcodegen generate`): он не компилируется и не покрывается тестами, поэтому
    по отчёту `xccov` такую потерю не увидеть. Сверка идёт по `path = <имя>;`
    в `project.pbxproj`, а не по отчёту покрытия: файлы без исполняемых строк
    (например, чистые записи) в отчёт не попадают, но должны быть в проекте.
    """
    if not project.exists():
        sys.exit(f"Нет проекта {project}: сначала запустите xcodegen generate.")
    text = project.read_text(encoding="utf-8")
    return sorted(
        path.name
        for path in Path(scope).rglob("*.swift")
        if f"path = {path.name};" not in text
    )


def main() -> int:
    args = parse_args()
    report = load_report(Path(args.bundle))
    files, app_target = collect(report, args.scope)

    if not files:
        print(f"Не найдены файлы покрытия в {args.scope}: порог нельзя подтвердить.", file=sys.stderr)
        return 2

    missing = files_missing_from_project(args.scope, Path(args.project))
    if missing:
        print(
            f"В проекте нет файлов из {args.scope}: {', '.join(missing)}. "
            "Запустите xcodegen generate и повторите тесты.",
            file=sys.stderr,
        )
        return 2

    files.sort(key=lambda item: item["path"])
    print(f"{'Строк':>7} {'Покрыто':>8} {'%':>7}  Файл")
    for file in files:
        executable = file.get("executableLines", 0)
        covered = file.get("coveredLines", 0)
        print(
            f"{executable:>7} {covered:>8} {percent(covered, executable):>7.1f}  "
            f"{Path(file['path']).name}"
        )

    executable = sum(file.get("executableLines", 0) for file in files)
    covered = sum(file.get("coveredLines", 0) for file in files)
    total = percent(covered, executable)

    if app_target is not None:
        app_executable = app_target.get("executableLines", 0)
        app_covered = app_target.get("coveredLines", 0)
        print(
            f"\nСправочно: всё приложение — {percent(app_covered, app_executable):.1f}% "
            f"({app_covered}/{app_executable}); представления проверяются XCUITest."
        )

    print(f"Порог {args.threshold:.0f}% по {args.scope}: {total:.1f}% ({covered}/{executable})")

    if total + 1e-9 < args.threshold:
        print(f"Покрытие ниже порога на {args.threshold - total:.1f} п.п.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
