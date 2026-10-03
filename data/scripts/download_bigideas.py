"""Download BIG IDEAs (PhysioNet v1.1.3) files to your PC, verified by SHA-256.

Runs on Windows, macOS or Linux with only the Python standard library.
Run it from the repo root (the folder that contains data/):

    py data\\scripts\\download_bigideas.py              # Wave 1: Dexcom, HR, food logs, Demographics (~220 MB)
    py data\\scripts\\download_bigideas.py --wave 2     # + ACC (32 Hz, ~13 GB, aggregate on arrival)
    py data\\scripts\\download_bigideas.py --wave 3     # + EDA, TEMP, IBI (~2.5 GB)
    py data\\scripts\\download_bigideas.py --participants 001 002   # only some people

Files land in data/raw/bigideas_1.1.3/<ID>/... (git-ignored by data/.gitignore).
Re-running skips files whose checksum already matches, and resumes partial downloads.
BVP (64 Hz, the biggest file) is never downloaded unless you pass --include-bvp.
"""
import argparse
import hashlib
import sys
import time
import urllib.request
from pathlib import Path

BASE = "https://physionet.org/files/big-ideas-glycemic-wearable/1.1.3/"
WAVES = {
    1: ("Dexcom", "HR", "Food_Log"),
    2: ("ACC",),
    3: ("EDA", "TEMP", "IBI"),
}
ROOT_FILES = ("Demographics.csv", "LICENSE.txt", "SHA256SUMS.txt")
USER_AGENT = "gummi-hackathon-downloader/1.0 (python urllib)"


def fetch(url: str, dest: Path, retries: int = 4) -> None:
    """Download url to dest, resuming a partial .part file when possible."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    for attempt in range(1, retries + 1):
        have = part.stat().st_size if part.exists() else 0
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        if have:
            req.add_header("Range", f"bytes={have}-")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                resumed = resp.status == 206
                mode = "ab" if resumed else "wb"
                total = resp.headers.get("Content-Length")
                total = int(total) + (have if resumed else 0) if total else None
                done = have if resumed else 0
                last = time.time()
                with open(part, mode) as fh:
                    while True:
                        chunk = resp.read(1 << 20)
                        if not chunk:
                            break
                        fh.write(chunk)
                        done += len(chunk)
                        if time.time() - last > 2:
                            pct = f"{100 * done / total:5.1f}%" if total else ""
                            print(f"    {dest.name}: {done / 1e6:8.1f} MB {pct}", flush=True)
                            last = time.time()
            part.replace(dest)
            return
        except Exception as exc:  # network hiccup: retry with resume
            print(f"    attempt {attempt}/{retries} failed for {dest.name}: {exc}", flush=True)
            time.sleep(3 * attempt)
    raise RuntimeError(f"giving up on {url}")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wave", type=int, default=1, choices=(1, 2, 3), help="download waves 1..N (default 1)")
    ap.add_argument("--participants", nargs="*", default=[f"{i:03d}" for i in range(1, 17)])
    ap.add_argument("--include-bvp", action="store_true", help="also download BVP (64 Hz, very large)")
    ap.add_argument("--base", default=BASE, help=argparse.SUPPRESS)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[1] / "raw" / "bigideas_1.1.3"))
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"Saving to {out}")

    for name in ROOT_FILES:
        if not (out / name).exists():
            print(f"  {name}")
            fetch(args.base + name, out / name)

    sums = {}
    for line in (out / "SHA256SUMS.txt").read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            sums[parts[1].lstrip("*").lstrip("./")] = parts[0]

    prefixes = [p for w in range(1, args.wave + 1) for p in WAVES[w]]
    if args.include_bvp:
        prefixes.append("BVP")

    wanted = []
    for rel in sorted(sums):
        pid = rel.split("/")[0]
        fname = rel.split("/")[-1]
        if pid in args.participants and any(fname.startswith(p + "_") for p in prefixes):
            wanted.append(rel)
    if "Demographics.csv" in sums:
        wanted.insert(0, "Demographics.csv")

    print(f"{len(wanted)} files to check (waves 1..{args.wave}, {len(args.participants)} participants)")
    bad = []
    for rel in wanted:
        dest = out / rel
        if dest.exists() and sha256(dest) == sums[rel]:
            print(f"  ok      {rel}")
            continue
        print(f"  fetch   {rel}")
        fetch(args.base + rel, dest)
        if sha256(dest) != sums[rel]:
            print(f"  CHECKSUM MISMATCH {rel}")
            bad.append(rel)
        else:
            print(f"  verified {rel}")

    if bad:
        print(f"\n{len(bad)} file(s) failed verification. Delete them and re-run:")
        for rel in bad:
            print("   ", rel)
        return 1
    print("\nAll files verified against SHA256SUMS.txt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
