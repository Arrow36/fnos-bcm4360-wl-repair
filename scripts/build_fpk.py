#!/usr/bin/env python3
"""Build a reproducible, manually installable fnOS FPK package."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSION = "1.0.0"
FPK_SOURCE = ROOT / "packaging" / "fpk"
INSTALLER_SOURCE = ROOT / "src" / "fnos-bcm4360-oneclick.sh"
DEFAULT_OUTPUT_DIR = ROOT / "dist"
DEFAULT_CACHE_DIR = ROOT / ".cache"

DRIVER_NAME = "broadcom-sta-dkms_6.30.223.271-30_amd64.deb"
DRIVER_URL = (
    "https://deb.debian.org/debian/pool/non-free/b/broadcom-sta/" + DRIVER_NAME
)
DRIVER_SHA256 = "34917b5662cb03c453d28c834c229f20ace9fecd481c7bd9d8a789e1cc87fec5"
FPK_NAME = f"fnos-bcm4360-wl-repair_{VERSION}_x86_64.fpk"
FIXED_MTIME = 1_785_283_200


def digest(path: Path, algorithm: str = "sha256") -> str:
    hasher = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def digest_bytes(payload: bytes, algorithm: str = "sha256") -> str:
    return hashlib.new(algorithm, payload).hexdigest()


def checked_driver(path: Path) -> Path:
    if not path.is_file():
        raise RuntimeError(f"驱动包不存在：{path}")
    actual = digest(path)
    if actual != DRIVER_SHA256:
        raise RuntimeError(
            f"驱动包 SHA-256 不匹配：期望 {DRIVER_SHA256}，实际 {actual}"
        )
    return path


def download_driver(target: Path) -> Path:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix="broadcom-sta-", suffix=".deb", dir=target.parent, delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)

    try:
        request = urllib.request.Request(
            DRIVER_URL,
            headers={"User-Agent": "fnos-bcm4360-wl-repair-builder/1.0"},
        )
        print(f"下载固定版本驱动包：{DRIVER_URL}")
        with urllib.request.urlopen(request, timeout=60) as response:
            with temporary_path.open("wb") as output:
                shutil.copyfileobj(response, output)
        checked_driver(temporary_path)
        temporary_path.replace(target)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise

    return target


def resolve_driver(explicit_path: Path | None, allow_download: bool) -> Path:
    if explicit_path is not None:
        return checked_driver(explicit_path.resolve())

    cached = DEFAULT_CACHE_DIR / DRIVER_NAME
    if cached.is_file():
        return checked_driver(cached)
    if not allow_download:
        raise RuntimeError(
            f"缓存中没有 {DRIVER_NAME}；请去掉 --no-download 或使用 --driver PATH"
        )
    return download_driver(cached)


def read_ar_members(path: Path) -> dict[str, bytes]:
    """Read the simple ar layout used by Debian binary packages."""
    payload = path.read_bytes()
    if not payload.startswith(b"!<arch>\n"):
        raise RuntimeError(f"不是有效的 Debian/ar 包：{path}")

    members: dict[str, bytes] = {}
    offset = 8
    while offset < len(payload):
        if offset + 60 > len(payload):
            raise RuntimeError("Debian 包的 ar 头被截断")
        header = payload[offset : offset + 60]
        if header[58:60] != b"`\n":
            raise RuntimeError("Debian 包含无效的 ar 成员头")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        start = offset + 60
        end = start + size
        if end > len(payload):
            raise RuntimeError(f"Debian 包成员被截断：{name}")
        members[name] = payload[start:end]
        offset = end + (size % 2)
    return members


def extract_driver_copyright(driver: Path) -> bytes:
    members = read_ar_members(driver)
    data_name = next(
        (name for name in members if name.startswith("data.tar.")), None
    )
    if data_name is None:
        raise RuntimeError("Debian 包中缺少 data.tar 载荷")
    if data_name.endswith(".zst"):
        raise RuntimeError("当前 Python 不支持读取 zstd Debian 载荷")

    with tarfile.open(fileobj=io.BytesIO(members[data_name]), mode="r:*") as archive:
        candidates = {
            member.name.removeprefix("./"): member
            for member in archive.getmembers()
            if member.isfile()
        }
        name = "usr/share/doc/broadcom-sta-dkms/copyright"
        member = candidates.get(name)
        if member is None:
            raise RuntimeError(f"Debian 包中缺少许可证文件：{name}")
        stream = archive.extractfile(member)
        if stream is None:
            raise RuntimeError(f"无法读取 Debian 包许可证文件：{name}")
        return stream.read()


def tar_info(name: str, size: int, mode: int) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name.replace("\\", "/"))
    info.size = size
    info.mtime = FIXED_MTIME
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    return info


def add_bytes(
    archive: tarfile.TarFile, name: str, payload: bytes, mode: int = 0o644
) -> None:
    archive.addfile(tar_info(name, len(payload), mode), io.BytesIO(payload))


def add_directory(archive: tarfile.TarFile, name: str) -> None:
    info = tar_info(name.rstrip("/"), 0, 0o755)
    info.type = tarfile.DIRTYPE
    archive.addfile(info)


def deterministic_tgz(writer) -> bytes:
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
        writer(archive)
    return gzip.compress(tar_buffer.getvalue(), compresslevel=9, mtime=FIXED_MTIME)


def build_app_tgz(driver: Path) -> bytes:
    copyright_text = extract_driver_copyright(driver)

    def write_app(archive: tarfile.TarFile) -> None:
        for path in sorted((FPK_SOURCE / "app").rglob("*")):
            if path.is_file():
                add_bytes(
                    archive,
                    path.relative_to(FPK_SOURCE / "app").as_posix(),
                    path.read_bytes(),
                )
        add_bytes(
            archive,
            "bin/fnos-bcm4360-oneclick.sh",
            INSTALLER_SOURCE.read_bytes(),
            0o755,
        )
        add_bytes(archive, f"packages/{DRIVER_NAME}", driver.read_bytes())
        add_bytes(
            archive,
            "THIRD_PARTY_LICENSES/broadcom-sta-dkms-copyright",
            copyright_text,
        )

    return deterministic_tgz(write_app)


def validate_sources() -> None:
    required = [
        INSTALLER_SOURCE,
        FPK_SOURCE / "manifest",
        FPK_SOURCE / "ICON.PNG",
        FPK_SOURCE / "ICON_256.PNG",
        FPK_SOURCE / "config" / "privilege",
        FPK_SOURCE / "config" / "resource",
        FPK_SOURCE / "cmd" / "main",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError(f"缺少构建输入：{missing}")
    for name in ("privilege", "resource"):
        json.loads((FPK_SOURCE / "config" / name).read_text(encoding="utf-8"))


def build_fpk(app_tgz: bytes) -> bytes:
    app_md5 = digest_bytes(app_tgz, "md5")
    source_manifest = (FPK_SOURCE / "manifest").read_text(encoding="utf-8")
    manifest = (source_manifest.rstrip() + f"\nchecksum = {app_md5}\n").encode()

    def write_outer(archive: tarfile.TarFile) -> None:
        add_bytes(archive, "app.tgz", app_tgz)
        add_bytes(archive, "manifest", manifest)
        for icon in ("ICON.PNG", "ICON_256.PNG"):
            add_bytes(archive, icon, (FPK_SOURCE / icon).read_bytes())
        for folder in ("cmd", "config", "wizard"):
            add_directory(archive, folder)
            for path in sorted((FPK_SOURCE / folder).rglob("*")):
                if path.is_file():
                    mode = 0o755 if folder == "cmd" else 0o644
                    add_bytes(
                        archive,
                        path.relative_to(FPK_SOURCE).as_posix(),
                        path.read_bytes(),
                        mode,
                    )

    return deterministic_tgz(write_outer)


def write_outputs(output_dir: Path, fpk: bytes) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    fpk_path = output_dir / FPK_NAME
    installer_path = output_dir / INSTALLER_SOURCE.name
    fpk_path.write_bytes(fpk)
    shutil.copyfile(INSTALLER_SOURCE, installer_path)

    files = (fpk_path, installer_path)
    checksum_lines = [f"{digest(path)}  {path.name}" for path in files]
    (output_dir / "SHA256SUMS.txt").write_text(
        "\n".join(checksum_lines) + "\n", encoding="utf-8", newline="\n"
    )
    return fpk_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--driver",
        type=Path,
        help="使用指定的 broadcom-sta-dkms Debian 包（仍会校验 SHA-256）",
    )
    parser.add_argument(
        "--no-download",
        action="store_true",
        help="缓存缺失时不从 Debian 下载驱动包",
    )
    parser.add_argument(
        "--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="产物目录"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    validate_sources()
    driver = resolve_driver(args.driver, allow_download=not args.no_download)
    app_tgz = build_app_tgz(driver)
    fpk = build_fpk(app_tgz)
    output = write_outputs(args.output_dir.resolve(), fpk)
    print(f"FPK: {output}")
    print(f"FPK SHA-256: {digest(output)}")
    print(f"app.tgz MD5: {digest_bytes(app_tgz, 'md5')}")


if __name__ == "__main__":
    main()
