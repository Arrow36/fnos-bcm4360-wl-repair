#!/usr/bin/env python3
"""Verify fnOS FPK structure, integrity and embedded third-party notices."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSION = "1.0.0"
DEFAULT_PACKAGE = ROOT / "dist" / f"fnos-bcm4360-wl-repair_{VERSION}_x86_64.fpk"
SOURCE_INSTALLER = ROOT / "src" / "fnos-bcm4360-oneclick.sh"
DRIVER_NAME = "broadcom-sta-dkms_6.30.223.271-30_amd64.deb"
DRIVER_SHA256 = "34917b5662cb03c453d28c834c229f20ace9fecd481c7bd9d8a789e1cc87fec5"


def digest(payload: bytes, algorithm: str = "sha256") -> str:
    return hashlib.new(algorithm, payload).hexdigest()


def safe_members(archive: tarfile.TarFile) -> dict[str, tarfile.TarInfo]:
    result: dict[str, tarfile.TarInfo] = {}
    for member in archive.getmembers():
        name = member.name.rstrip("/")
        if name.startswith("/") or ".." in Path(name).parts:
            raise RuntimeError(f"不安全的归档路径：{member.name}")
        if member.issym() or member.islnk():
            raise RuntimeError(f"归档中不允许链接：{member.name}")
        result[name] = member
    return result


def read_member(
    archive: tarfile.TarFile, members: dict[str, tarfile.TarInfo], name: str
) -> bytes:
    member = members.get(name)
    if member is None or not member.isfile():
        raise RuntimeError(f"缺少文件：{name}")
    stream = archive.extractfile(member)
    if stream is None:
        raise RuntimeError(f"无法读取文件：{name}")
    return stream.read()


def png_dimensions(payload: bytes) -> tuple[int, int]:
    if payload[:8] != b"\x89PNG\r\n\x1a\n" or payload[12:16] != b"IHDR":
        raise RuntimeError("图标不是有效 PNG")
    return struct.unpack(">II", payload[16:24])


def manifest_values(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def verify(package: Path) -> dict[str, object]:
    with tarfile.open(package, "r:gz") as outer:
        outer_members = safe_members(outer)
        required_outer = {
            "app.tgz",
            "manifest",
            "ICON.PNG",
            "ICON_256.PNG",
            "config/privilege",
            "config/resource",
            "cmd/install_init",
            "cmd/install_callback",
            "cmd/main",
            "wizard",
        }
        missing = required_outer - outer_members.keys()
        if missing:
            raise RuntimeError(f"FPK 缺少条目：{sorted(missing)}")

        manifest = read_member(outer, outer_members, "manifest").decode("utf-8")
        values = manifest_values(manifest)
        if values.get("appname") != "bcm4360-wl-repair":
            raise RuntimeError("manifest appname 不正确")
        if values.get("version") != VERSION:
            raise RuntimeError("manifest version 不正确")

        app_tgz = read_member(outer, outer_members, "app.tgz")
        actual_md5 = digest(app_tgz, "md5")
        if values.get("checksum") != actual_md5:
            raise RuntimeError("manifest checksum 与 app.tgz 不一致")

        icon_sizes: dict[str, str] = {}
        for name, expected in (("ICON.PNG", (64, 64)), ("ICON_256.PNG", (256, 256))):
            size = png_dimensions(read_member(outer, outer_members, name))
            if size != expected:
                raise RuntimeError(f"{name} 尺寸错误：{size}")
            icon_sizes[name] = f"{size[0]}x{size[1]}"

        for name in ("config/privilege", "config/resource"):
            json.loads(read_member(outer, outer_members, name).decode("utf-8"))

        for name, member in outer_members.items():
            if name.startswith("cmd/") and member.isfile():
                payload = read_member(outer, outer_members, name)
                if member.mode & 0o111 == 0:
                    raise RuntimeError(f"生命周期脚本不可执行：{name}")
                if not payload.startswith(b"#!/bin/bash\n") or b"\r\n" in payload:
                    raise RuntimeError(f"生命周期脚本格式错误：{name}")

    with tarfile.open(fileobj=io.BytesIO(app_tgz), mode="r:gz") as app:
        app_members = safe_members(app)
        installer_name = "bin/fnos-bcm4360-oneclick.sh"
        driver_name = f"packages/{DRIVER_NAME}"
        license_name = "THIRD_PARTY_LICENSES/broadcom-sta-dkms-copyright"
        installer = read_member(app, app_members, installer_name)
        driver = read_member(app, app_members, driver_name)
        license_text = read_member(app, app_members, license_name)

        if digest(installer) != digest(SOURCE_INSTALLER.read_bytes()):
            raise RuntimeError("FPK 内脚本与 src/ 中的脚本不一致")
        if digest(driver) != DRIVER_SHA256:
            raise RuntimeError("FPK 内驱动包 SHA-256 不正确")
        if b"Broadcom" not in license_text or b"License" not in license_text:
            raise RuntimeError("随附的 Broadcom/Debian 许可证文本异常")
        if app_members[installer_name].mode & 0o111 == 0 or b"\r\n" in installer:
            raise RuntimeError("FPK 内脚本权限或换行符错误")

    package_payload = package.read_bytes()
    return {
        "package": str(package),
        "bytes": len(package_payload),
        "sha256": digest(package_payload),
        "app_tgz_md5": actual_md5,
        "driver_sha256": digest(driver),
        "installer_sha256": digest(installer),
        "icons": icon_sizes,
        "third_party_license": True,
        "result": "PASS",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", nargs="?", type=Path, default=DEFAULT_PACKAGE)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    print(json.dumps(verify(args.package.resolve()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
