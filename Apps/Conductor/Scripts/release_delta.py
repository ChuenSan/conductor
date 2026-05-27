#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shutil
import stat
from pathlib import Path


def file_digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def bundle_entries(root: Path) -> dict[str, dict[str, object]]:
    entries: dict[str, dict[str, object]] = {}
    for current, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name != ".DS_Store"]
        for name in files:
            if name == ".DS_Store":
                continue
            path = Path(current) / name
            rel = path.relative_to(root).as_posix()
            info = path.lstat()
            if path.is_symlink():
                entries[rel] = {
                    "kind": "symlink",
                    "target": os.readlink(path),
                    "mode": stat.S_IMODE(info.st_mode),
                }
            else:
                entries[rel] = {
                    "kind": "file",
                    "sha256": file_digest(path),
                    "size": info.st_size,
                    "mode": stat.S_IMODE(info.st_mode),
                }
    return entries


def copy_entry(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        if destination.exists() or destination.is_symlink():
            destination.unlink()
        os.symlink(os.readlink(source), destination)
        return
    shutil.copy2(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a file-level Conductor app delta payload.")
    parser.add_argument("--old-app", required=True)
    parser.add_argument("--new-app", required=True)
    parser.add_argument("--payload-dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--created-at", required=True)
    args = parser.parse_args()

    old_app = Path(args.old_app).resolve()
    new_app = Path(args.new_app).resolve()
    payload_dir = Path(args.payload_dir).resolve()
    manifest_path = Path(args.manifest).resolve()

    old_entries = bundle_entries(old_app)
    new_entries = bundle_entries(new_app)

    changed: list[dict[str, object]] = []
    removed: list[str] = []

    for rel, new_info in sorted(new_entries.items()):
        if old_entries.get(rel) != new_info:
            source = new_app / rel
            destination = payload_dir / "Conductor.app" / rel
            copy_entry(source, destination)
            changed.append({"path": rel, **new_info})

    for rel in sorted(set(old_entries) - set(new_entries)):
        removed.append(rel)

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(
            {
                "schemaVersion": 1,
                "strategy": "file-delta",
                "version": args.version,
                "build": args.build,
                "createdAt": args.created_at,
                "changed": changed,
                "removed": removed,
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )
        handle.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
