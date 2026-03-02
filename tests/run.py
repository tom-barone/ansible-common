#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml

TESTS_DIR = Path("./tests").resolve()
ROLES_DIR = Path("./roles").resolve()
MOLECULE_DOCKER_IMAGE = "geerlingguy/docker-debian13-ansible:latest"  # Trixie
PROXMOX_ISO_URL = "https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
CACHE_DIR = Path(".cache").resolve()


def get_driver_name(scenario_path: Path) -> str:
    molecule_yml = scenario_path / "molecule.yml"
    with molecule_yml.open() as f:
        config = yaml.safe_load(f)
    return config.get("driver", {}).get("name", "default")


def find_molecule_scenarios(root: Path):
    for yml in root.rglob("molecule.yml"):
        # match */molecule/<scenario>/molecule.yml
        if yml.parent.parent.name == "molecule":
            yield yml.parent


def run_test(path: Path, no_capture: bool):
    test_dir = path.parent
    cmd = ["uv", "run", "molecule", "--debug", "test"]
    env = {
        **os.environ.copy(),
        "TEST_NAME": str(test_dir.relative_to(TESTS_DIR)).replace(os.sep, "_"),
        "ANSIBLE_ROLES_PATH": str(ROLES_DIR),
        "MOLECULE_DOCKER_IMAGE": MOLECULE_DOCKER_IMAGE,
        "CACHE_DIR": str(CACHE_DIR),
    }

    if no_capture:
        # Print output directly to console without capturing
        result = subprocess.run(
            cmd,
            cwd=test_dir.parent,
            env=env,
            text=True,
        )
    else:
        result = subprocess.run(
            cmd,
            cwd=test_dir.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            text=True,
        )
    return path, result.returncode, result.stdout if no_capture else ""


def download_proxmox_image():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    filename = PROXMOX_ISO_URL.split("/")[-1]
    dest = CACHE_DIR / filename

    # Cache hit
    if dest.exists() and dest.stat().st_size > 0:
        return dest

    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(
        PROXMOX_ISO_URL, headers={"User-Agent": "iso-downloader/1.0"}
    )

    with urllib.request.urlopen(req) as r, tmp.open("wb") as f:
        shutil.copyfileobj(r, f)

    tmp.replace(dest)  # atomic move


def main():
    parser = argparse.ArgumentParser(description="Run molecule tests")
    parser.add_argument(
        "--name", help="filter scenarios by substring match on relative path"
    )
    parser.add_argument(
        "--no-capture",
        help="print test output directly to console",
        action="store_true",
    )
    parser.add_argument(
        "--include-vm",
        help="include non-Docker scenarios (e.g. QEMU-based PVE tests)",
        action="store_true",
    )

    args = parser.parse_args()

    scenarios = list(find_molecule_scenarios(TESTS_DIR))
    download_proxmox_image()

    if not args.include_vm:
        scenarios = [s for s in scenarios if get_driver_name(s) == "docker"]

    if args.name:
        scenarios = [s for s in scenarios if args.name in str(s.relative_to(TESTS_DIR))]

    print(f"Found {len(scenarios)} molecule scenarios. Running tests...")

    if not scenarios:
        print("No molecule scenarios found.")
        return 1

    max_workers = os.cpu_count() or 1
    failures = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(run_test, s, args.no_capture) for s in scenarios]

        for future in as_completed(futures):
            path, rc, output = future.result()
            if rc == 0:
                # single dot for success
                print(".", end="", flush=True)
            else:
                failures.append((path, output))
                print("E", end="", flush=True)

    print()  # newline after dots, errors

    if failures:
        for _, output in failures:
            print(output)
            print("-" * 40)

        print("\nFailures:")
        for path, _ in failures:
            print(f" - {path}")
        return 1

    print("\nAll molecule tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
