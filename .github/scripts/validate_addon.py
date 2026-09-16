#!/usr/bin/env python3
"""Validate Home Assistant add-on metadata before the container build.

Catches the mistakes that otherwise only surface inside the Supervisor:
bad YAML/JSON, a missing required key, an unknown CPU arch, and options or
ports that are declared without a matching schema/description entry.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
ADDON_DIR = REPO_ROOT / "cups"
CONFIG_PATH = ADDON_DIR / "config.yaml"
REPOSITORY_PATH = REPO_ROOT / "repository.json"
CHANGELOG_PATH = REPO_ROOT / "CHANGELOG.md"

REQUIRED_KEYS = ("name", "version", "slug", "description", "arch", "startup")
VALID_ARCHES = {"aarch64", "amd64", "armv7", "armhf", "i386"}
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
CHANGELOG_VERSION = re.compile(r"^##\s+\[(\d+\.\d+\.\d+)\]", re.MULTILINE)
PORT_KEY = re.compile(r"^\d+/(tcp|udp)$")
MAP_ENTRY = re.compile(r"^[A-Za-z0-9_.-]+:(rw|ro)$")

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def load_yaml(path: Path):
    if not path.is_file():
        fail(f"{path.relative_to(REPO_ROOT)}: file not found")
        return None
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        fail(f"{path.relative_to(REPO_ROOT)}: invalid YAML: {exc}")
        return None


def validate_repository_json() -> None:
    if not REPOSITORY_PATH.is_file():
        fail("repository.json: file not found")
        return
    try:
        data = json.loads(REPOSITORY_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"repository.json: invalid JSON: {exc}")
        return
    for key in ("name", "url", "maintainer"):
        if not data.get(key):
            fail(f"repository.json: missing or empty '{key}'")


def validate_arch(config: dict) -> None:
    arch = config.get("arch")
    if not isinstance(arch, list) or not arch:
        fail("config.yaml: 'arch' must be a non-empty list")
        return
    if len(set(arch)) != len(arch):
        fail(f"config.yaml: 'arch' has duplicates: {arch}")
    unknown = [a for a in arch if a not in VALID_ARCHES]
    if unknown:
        fail(f"config.yaml: unknown arch value(s) {unknown}; allowed: {sorted(VALID_ARCHES)}")
    if "amd64" not in arch:
        fail("config.yaml: 'arch' must include amd64 (CI builds linux/amd64)")


def validate_version(config: dict) -> None:
    version = str(config.get("version", ""))
    if not SEMVER.match(version):
        fail(f"config.yaml: 'version' must be X.Y.Z, got {version!r}")
        return
    if not CHANGELOG_PATH.is_file():
        fail("CHANGELOG.md: file not found")
        return
    match = CHANGELOG_VERSION.search(CHANGELOG_PATH.read_text(encoding="utf-8"))
    if not match:
        fail("CHANGELOG.md: no '## [X.Y.Z]' release heading found")
    elif match.group(1) != version:
        fail(
            f"version mismatch: config.yaml has {version}, "
            f"CHANGELOG.md latest heading is {match.group(1)}"
        )


def validate_symmetry(config: dict, declared: str, described: str) -> None:
    left = config.get(declared)
    right = config.get(described)
    if left is None and right is None:
        return
    if not isinstance(left, dict) or not isinstance(right, dict):
        fail(f"config.yaml: '{declared}' and '{described}' must both be mappings")
        return
    for key in sorted(set(left) - set(right)):
        fail(f"config.yaml: '{declared}' entry {key!r} has no '{described}' entry")
    for key in sorted(set(right) - set(left)):
        fail(f"config.yaml: '{described}' entry {key!r} has no '{declared}' entry")


def validate_options_schema(config: dict) -> None:
    options = config.get("options") or {}
    schema = config.get("schema") or {}
    if not isinstance(options, dict) or not isinstance(schema, dict):
        fail("config.yaml: 'options' and 'schema' must both be mappings")
        return
    for key in sorted(set(options) - set(schema)):
        fail(f"config.yaml: option {key!r} has no 'schema' entry")
    for key in sorted(set(schema) - set(options)):
        fail(f"config.yaml: schema entry {key!r} has no 'options' default")


def validate_ports(config: dict) -> None:
    validate_symmetry(config, "ports", "ports_description")
    for key in sorted(config.get("ports") or {}):
        if not PORT_KEY.match(str(key)):
            fail(f"config.yaml: port key {key!r} must look like '631/tcp'")


def validate_map(config: dict) -> None:
    for entry in config.get("map") or []:
        if not MAP_ENTRY.match(str(entry)):
            fail(f"config.yaml: map entry {entry!r} must look like 'share:rw'")


def validate_slug(config: dict) -> None:
    slug = config.get("slug")
    if slug != ADDON_DIR.name:
        fail(f"config.yaml: slug {slug!r} must match add-on directory {ADDON_DIR.name!r}")


def main() -> int:
    validate_repository_json()

    config = load_yaml(CONFIG_PATH)
    if config is None:
        for message in errors:
            print(f"::error::{message}")
        return 1
    if not isinstance(config, dict):
        print("::error::config.yaml: top level must be a mapping")
        return 1

    for key in REQUIRED_KEYS:
        if config.get(key) in (None, "", [], {}):
            fail(f"config.yaml: missing or empty required key '{key}'")

    validate_slug(config)
    validate_arch(config)
    validate_version(config)
    validate_options_schema(config)
    validate_ports(config)
    validate_map(config)

    if errors:
        for message in errors:
            print(f"::error::{message}")
        print(f"\n{len(errors)} add-on metadata problem(s) found.")
        return 1

    print(f"add-on metadata OK: {ADDON_DIR.name} {config['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
