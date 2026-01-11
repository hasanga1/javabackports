#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

def find_module_for_file(repo, filepath):
    """Find the Maven module (directory with pom.xml) for a given file."""
    current_dir = os.path.dirname(filepath) if filepath else ""
    while current_dir:
        pom_path = os.path.join(repo, current_dir, "pom.xml")
        if os.path.exists(pom_path):
            return current_dir
        parent = os.path.dirname(current_dir)
        if parent == current_dir:
            break
        current_dir = parent
    return None

def extract_test_class(filepath):
    """Extract the fully qualified test class name from a test file path."""
    # Accept both src/test/java and src/androidTest/java
    if "/src/test/java/" in filepath:
        rel = filepath.split("/src/test/java/")[-1]
    elif "/src/androidTest/java/" in filepath:
        rel = filepath.split("/src/androidTest/java/")[-1]
    else:
        return None
    if not rel.endswith("Test.java"):
        return None
    return rel[:-5].replace("/", ".")  # Remove .java, convert to FQCN

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the git repository")
    parser.add_argument("--commit", required=True, help="Commit hash to analyze")
    args = parser.parse_args()

    cmd = ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        print(json.dumps({"modified": [], "added": []}))
        return

    modified_tests = set()
    added_tests = set()

    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
        status, f = parts
        if not f.endswith("Test.java"):
            continue
        module = find_module_for_file(args.repo, f)
        test_class = extract_test_class(f)
        if not module or not test_class:
            continue
        target = f"{module}:{test_class}"
        if status == "A":
            added_tests.add(target)
        else:
            modified_tests.add(target)

    print(json.dumps({
        "modified": sorted(modified_tests),
        "added": sorted(added_tests)
    }))

if __name__ == "__main__":
    main()
