#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

TESTS_DIR = Path("./tests").resolve()
ROLES_DIR = Path("./roles").resolve()
MOLECULE_DOCKER_IMAGE = "geerlingguy/docker-debian13-ansible:latest"  # Trixie
CACHE_DIR = Path(".cache").resolve()
SSH_KEY = TESTS_DIR / "id_ed25519"
PROXMOX_IMAGE_PLAYBOOK = TESTS_DIR / "proxmox_setup_test_image.yml"
ENV = {
    **os.environ,
    "ANSIBLE_ROLES_PATH": str(ROLES_DIR),
    "MOLECULE_DOCKER_IMAGE": MOLECULE_DOCKER_IMAGE,
    "CACHE_DIR": str(CACHE_DIR),
    "ANSIBLE_PRIVATE_KEY_FILE": str(SSH_KEY),
    "TEST_SSH_PUBLIC_KEY": SSH_KEY.with_suffix(".pub").read_text().strip(),
}


def find_molecule_scenarios(root: Path):
    for yml in root.rglob("molecule.yml"):
        # match */molecule/<scenario>/molecule.yml
        if yml.parent.parent.name == "molecule":
            yield yml.parent


def run_test(path: Path, no_capture: bool):
    test_dir = path.parent
    cmd = ["uv", "run", "molecule", "--debug", "test"]
    env = {
        **ENV,
        "TEST_NAME": str(test_dir.relative_to(TESTS_DIR)).replace(os.sep, "_"),
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
    failed = result.returncode != 0
    print_output_to_console = no_capture or failed

    return path, result.returncode, result.stdout if print_output_to_console else ""


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
    args = parser.parse_args()

    # Git drops the file mode and ssh refuses a group or world readable key
    SSH_KEY.chmod(0o600)

    scenarios = list(find_molecule_scenarios(TESTS_DIR))

    if args.name:
        scenarios = [s for s in scenarios if args.name in str(s.relative_to(TESTS_DIR))]

    print(f"Found {len(scenarios)} molecule scenarios...")

    if any(s.parent.parent.name.startswith("proxmox_") for s in scenarios):
        # Build the shared Proxmox VE image once before scenarios run in parallel
        cmd = ["uv", "run", "ansible-playbook", str(PROXMOX_IMAGE_PLAYBOOK)]
        if subprocess.run(cmd, cwd=TESTS_DIR, env=ENV).returncode != 0:
            return 1

    if not scenarios:
        print("No molecule scenarios found.")
        return 1

    max_workers = max(1, (os.cpu_count() or 1) - 1)  # leave one CPU core free
    print(f"Running tests with {max_workers} parallel workers...")
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
