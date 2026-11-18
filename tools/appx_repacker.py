#!/usr/bin/env python3
"""
SDK-free pure-Python APPX / APPXBUNDLE packager with optional Win32 AppxSip signing.
Fixes OPC percent-decoded BlockMap paths (urllib.parse.unquote) and uses 64KB Z_FULL_FLUSH blocks.
"""
import argparse, base64, hashlib, io, os, re, shutil, struct, subprocess, urllib.parse, zipfile, zlib
from xml.sax.saxutils import escape


def deflate_64k_appx(data: bytes):
    """Deflate data in 64KB independent blocks (Z_FULL_FLUSH) compatible with APPX BlockMap."""
    if len(data) == 0:
        c = zlib.compressobj(6, zlib.DEFLATED, -15)
        return c.flush(zlib.Z_FINISH), []
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    out = bytearray()
    blocks = []
    pos = 0
    while pos < len(data):
        chunk = data[pos:pos + 65536]
        h = base64.b64encode(hashlib.sha256(chunk).digest()).decode()
        pos += len(chunk)
        part = c.compress(chunk)
        part += c.flush(zlib.Z_FULL_FLUSH if pos < len(data) else zlib.Z_FINISH)
        out.extend(part)
        blocks.append((h, len(part)))
    return bytes(out), blocks


def write_zip_custom(out_path: str, entries):
    mtime, mdate = 0x6000, 0x535A
    cd_records = bytearray()
    meta = {}
    with open(out_path, "wb") as f:
        for name, data, store_only in entries:
            name_b = name.encode("utf-8")
            crc = zlib.crc32(data) & 0xFFFFFFFF
            usz = len(data)
            if store_only:
                meth = 0
                comp = data
                blocks = [(base64.b64encode(hashlib.sha256(data[p:p + 65536]).digest()).decode(), None)
                          for p in range(0, usz, 65536)] if usz > 0 else []
            else:
                meth = 8
                comp, blocks = deflate_64k_appx(data)
            csz = len(comp)
            flag = 0x0800
            hdr_off = f.tell()
            lfh = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, flag, meth, mtime, mdate, crc, csz, usz, len(name_b), 0)
            lfh_size = len(lfh) + len(name_b)
            payload_off = hdr_off + lfh_size
            f.write(lfh)
            f.write(name_b)
            f.write(comp)
            cd = struct.pack("<IHHHHHHIIIHHHHHII",
                             0x02014B50, 20, 20, flag, meth, mtime, mdate, crc, csz, usz, len(name_b), 0, 0, 0, 0, 0, hdr_off)
            cd_records.extend(cd)
            cd_records.extend(name_b)
            meta[name] = (lfh_size, payload_off, usz, blocks)
        cd_off = f.tell()
        f.write(cd_records)
        f.write(struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries), len(cd_records), cd_off, 0))
    return meta


def sign_package(target_path: str, pfx_path: str, password: str, sign_ps1: str):
    res = subprocess.run([
        "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", sign_ps1, "-TargetPath", target_path, "-PfxPath", pfx_path, "-Password", password
    ], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Signing failed for {target_path}:\n{res.stdout}\n{res.stderr}")


def build_content_types_for_appx(arcnames, orig_ct_bytes=None):
    ext_map = {
        "ini": "application/octet-stream", "exe": "application/x-msdownload", "config": "application/octet-stream",
        "pow": "application/octet-stream", "dll": "application/x-msdownload", "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "pri": "application/octet-stream",
        "xml": "application/vnd.ms-appx.manifest+xml", "json": "application/json", "txt": "text/plain",
        "bat": "application/octet-stream", "cmd": "application/octet-stream", "inf": "application/octet-stream",
        "cat": "application/octet-stream", "sys": "application/octet-stream", "ico": "image/vnd.microsoft.icon",
        "winmd": "application/x-msdownload",
    }
    if orig_ct_bytes:
        for ext, ctype in re.findall(r'<Default\s+Extension="([^"]+)"\s+ContentType="([^"]+)"\s*/>',
                                     orig_ct_bytes.decode("utf-8", "ignore")):
            ext_map[ext.lower()] = ctype
    exts, seen = [], set()
    for name in arcnames + ["AppxManifest.xml", "AppxBlockMap.xml"]:
        if "." in name.rsplit("/", 1)[-1]:
            ext = name.rsplit(".", 1)[-1].lower()
            if ext not in seen:
                seen.add(ext)
                exts.append((ext, ext_map.get(ext, "application/octet-stream")))
    defaults = "".join(f'<Default Extension="{escape(e)}" ContentType="{escape(ct)}"/>' for e, ct in exts)
    overrides = ('<Override PartName="/AppxManifest.xml" ContentType="application/vnd.ms-appx.manifest+xml"/>'
                 '<Override PartName="/AppxBlockMap.xml" ContentType="application/vnd.ms-appx.blockmap+xml"/>')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
            f'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">{defaults}{overrides}</Types>').encode("utf-8")


def build_appx_from_dir(src_dir: str, out_appx: str, pfx_path: str = None, password: str = None, sign_ps1: str = None):
    manifest_bytes = open(os.path.join(src_dir, "AppxManifest.xml"), "rb").read()
    orig_ct_path = os.path.join(src_dir, "[Content_Types].xml")
    orig_ct_bytes = open(orig_ct_path, "rb").read() if os.path.exists(orig_ct_path) else None

    payload_files, arcnames = [], []
    store_exts = (".png", ".jpg", ".jpeg", ".zip", ".7z", ".rar", ".mp3", ".mp4")
    for r, _, files in os.walk(src_dir):
        for fn in sorted(files):
            p = os.path.join(r, fn)
            rel = os.path.relpath(p, src_dir).replace("\\", "/")
            if rel in ("AppxBlockMap.xml", "AppxManifest.xml", "[Content_Types].xml", "AppxSignature.p7x", "AppxMetadata/CodeIntegrity.cat"):
                continue
            payload_files.append((rel, open(p, "rb").read(), rel.lower().endswith(store_exts)))
            arcnames.append(rel)

    ct_bytes = build_content_types_for_appx(arcnames, orig_ct_bytes)
    pre_entries = payload_files + [("AppxManifest.xml", manifest_bytes, False)]
    meta = write_zip_custom(out_appx, pre_entries)

    bm_parts = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\r\n'
        '<BlockMap xmlns="http://schemas.microsoft.com/appx/2010/blockmap" '
        'xmlns:b4="http://schemas.microsoft.com/appx/2021/blockmap" '
        'IgnorableNamespaces="b4" HashMethod="http://www.w3.org/2001/04/xmlenc#sha256">'
    ]
    for name, data, _ in pre_entries:
        lfh_sz, _, usz, blocks = meta[name]
        win_name = escape(urllib.parse.unquote(name).replace("/", "\\"))
        fhash = base64.b64encode(hashlib.sha256(data).digest()).decode()
        bm_parts.append(f'<File Name="{win_name}" Size="{usz}" LfhSize="{lfh_sz}">')
        for bh, bsz in blocks:
            bm_parts.append(f'<Block Hash="{bh}"/>' if bsz is None else f'<Block Hash="{bh}" Size="{bsz}"/>')
        bm_parts.append(f'<b4:FileHash Hash="{fhash}"/></File>')
    bm_parts.append('</BlockMap>')
    bm_bytes = "".join(bm_parts).encode("utf-8")

    write_zip_custom(out_appx, pre_entries + [("AppxBlockMap.xml", bm_bytes, False), ("[Content_Types].xml", ct_bytes, False)])
    if pfx_path and sign_ps1:
        sign_package(out_appx, pfx_path, password, sign_ps1)


def resign_existing_appx_bytes(appx_bytes: bytes, tmp_dir: str, name: str, pfx_path: str, password: str, sign_ps1: str) -> bytes:
    sub_dir = os.path.join(tmp_dir, f"_extract_{name}")
    if os.path.exists(sub_dir):
        shutil.rmtree(sub_dir)
    os.makedirs(sub_dir, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(appx_bytes)) as zf:
        zf.extractall(sub_dir)
    out_name = name if name.lower().endswith(".appx") else f"{name}.appx"
    out_appx = os.path.join(tmp_dir, f"_resigned_{out_name}")
    build_appx_from_dir(sub_dir, out_appx, pfx_path=pfx_path, password=password, sign_ps1=sign_ps1)
    return open(out_appx, "rb").read()


def build_appxbundle(inner_appx_map: dict, bundle_manifest_xml: bytes, out_bundle: str,
                     pfx_path: str = None, password: str = None, sign_ps1: str = None):
    bm_text = bundle_manifest_xml.decode("utf-8")
    cur_off = 0
    package_entries = []
    for fname, data in inner_appx_map.items():
        lfh_size = 30 + len(fname.encode("utf-8"))
        payload_off = cur_off + lfh_size
        size = len(data)
        cur_off = payload_off + size

        def repl_pkg(m):
            tag = re.sub(r'Offset="\d+"', f'Offset="{payload_off}"', m.group(0))
            return re.sub(r'Size="\d+"', f'Size="{size}"', tag)

        pat = r'<Package\b[^>]*FileName="' + re.escape(fname) + r'"[^>]*>'
        bm_text, n = re.subn(pat, repl_pkg, bm_text)
        if n != 1:
            raise RuntimeError(f"Expected 1 Package match for {fname} in AppxBundleManifest.xml, got {n}")
        package_entries.append((fname, data, True))

    pre_entries = package_entries + [("AppxMetadata/AppxBundleManifest.xml", bm_text.encode("utf-8"), False)]
    meta = write_zip_custom(out_bundle, pre_entries)

    lfh_sz, _, usz, blocks = meta["AppxMetadata/AppxBundleManifest.xml"]
    bm_parts = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\r\n'
        '<BlockMap xmlns="http://schemas.microsoft.com/appx/2010/blockmap" '
        'HashMethod="http://www.w3.org/2001/04/xmlenc#sha256">'
        f'<File Name="AppxMetadata\\AppxBundleManifest.xml" Size="{usz}" LfhSize="{lfh_sz}">'
    ]
    for bh, bsz in blocks:
        bm_parts.append(f'<Block Hash="{bh}" Size="{bsz}"/>')
    bm_parts.append('</File></BlockMap>')

    bundle_ct = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="appx" ContentType="application/vnd.ms-appx"/>'
        '<Default Extension="xml" ContentType="application/vnd.ms-appx.bundlemanifest+xml"/>'
        '<Override PartName="/AppxBlockMap.xml" ContentType="application/vnd.ms-appx.blockmap+xml"/>'
        '</Types>'
    ).encode("utf-8")

    write_zip_custom(out_bundle, pre_entries + [("AppxBlockMap.xml", "".join(bm_parts).encode("utf-8"), False), ("[Content_Types].xml", bundle_ct, False)])
    if pfx_path and sign_ps1:
        sign_package(out_bundle, pfx_path, password, sign_ps1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build & sign APPX from extracted directory")
    ap.add_argument("--src-dir", required=True, help="Extracted APPX payload directory containing AppxManifest.xml")
    ap.add_argument("--out-appx", required=True, help="Output .appx file path")
    ap.add_argument("--pfx", help="Optional .pfx file for signing")
    ap.add_argument("--password", default="cc_nohotkey", help="PFX password")
    ap.add_argument("--sign-ps1", help="Path to sign_appx.ps1")
    args = ap.parse_args()
    build_appx_from_dir(args.src_dir, args.out_appx, args.pfx, args.password, args.sign_ps1)
    print(f"Built {args.out_appx} ({os.path.getsize(args.out_appx)} bytes)")
