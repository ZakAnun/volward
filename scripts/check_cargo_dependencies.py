#!/usr/bin/env python3
"""Validate direct path dependencies between Cargo workspace members."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


DEFAULT_EXPECTED_EDGES = {
    "volward-index-pb:volward-core",
    "platform-desktop:volward-core",
    "volward-facade:platform-desktop",
    "volward-facade:volward-ai",
    "volward-facade:volward-core",
    "volward-facade:volward-index-pb",
    "volward-cli:platform-desktop",
    "volward-cli:volward-core",
    "volward-cli:volward-index-pb",
    "volward-platform-api:volward-ai",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--expected-edges")
    return parser.parse_args()


def load_expected_edges(path: str | None) -> set[str]:
    if path is None:
        return DEFAULT_EXPECTED_EDGES
    decoded = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(decoded, list) or not all(isinstance(item, str) for item in decoded):
        raise ValueError("--expected-edges must be a JSON array of strings")
    return set(decoded)


def cargo_metadata(root: Path) -> dict:
    completed = subprocess.run(
        [
            "cargo",
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--manifest-path",
            str(root / "Cargo.toml"),
        ],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "cargo metadata failed")
    return json.loads(completed.stdout)


def direct_workspace_edges(metadata: dict) -> set[str]:
    members = set(metadata["workspace_members"])
    packages = {package["id"]: package for package in metadata["packages"]}
    workspace_names = {packages[member]["name"] for member in members}
    edges: set[str] = set()

    for member in members:
        package = packages[member]
        source = package["name"]
        for dependency in package["dependencies"]:
            dependency_name = dependency["name"]
            if dependency.get("path") and dependency_name in workspace_names:
                edges.add(f"{source}:{dependency_name}")
    return edges


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    try:
        expected = load_expected_edges(args.expected_edges)
        actual = direct_workspace_edges(cargo_metadata(root))
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    undeclared = sorted(actual - expected)
    missing = sorted(expected - actual)
    if undeclared or missing:
        for edge in undeclared:
            print(f"undeclared internal Cargo edge: {edge}", file=sys.stderr)
        for edge in missing:
            print(f"missing internal Cargo edge: {edge}", file=sys.stderr)
        return 1

    print(f"cargo dependencies: OK ({len(actual)} edges)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
