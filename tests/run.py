#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

TESTS_DIR = Path("./tests").resolve()


def find_molecule_scenarios(root: Path):
    for yml in root.rglob("molecule.yml"):
        # match */molecule/<scenario>/molecule.yml
        if yml.parent.parent.name == "molecule":
            yield yml.parent


def run_test(path: Path):
    test_dir = path.parent.parent
    result = subprocess.run(
        ["uv", "run", "molecule", "test"],
        cwd=path.parent.parent,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env={
            **os.environ.copy(),
            "TEST_NAME": str(test_dir.relative_to(TESTS_DIR)).replace(os.sep, "_"),
        },
        text=True,
    )
    return path, result.returncode, result.stdout


def main():
    parser = argparse.ArgumentParser(description="Run molecule tests")
    parser.add_argument(
        "--name", help="filter scenarios by substring match on relative path"
    )
    args = parser.parse_args()

    scenarios = list(find_molecule_scenarios(TESTS_DIR))

    if args.name:
        scenarios = [s for s in scenarios if args.name in str(s.relative_to(TESTS_DIR))]

    print(f"Found {len(scenarios)} molecule scenarios. Running tests...")

    if not scenarios:
        print("No molecule scenarios found.")
        return 1

    max_workers = os.cpu_count() or 1
    failures = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(run_test, s) for s in scenarios]

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
