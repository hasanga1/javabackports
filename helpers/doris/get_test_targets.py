#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the git repository")
    parser.add_argument("--commit", required=True, help="Commit hash to analyze")
    args = parser.parse_args()

    # 1. Get list of changed files with status
    cmd = ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        print(json.dumps({"modified": [], "added": []}))
        return

    modified_tests = set()
    added_tests = set()
    has_fe_production_changes = False

    # 2. Analyze changes
    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
            
        status = parts[0]
        f = parts[1]

        if not f.endswith(".java"):
            continue

        # Check if this is a production change in FE
        if "fe/fe-core/src/main/java/" in f:
            has_fe_production_changes = True

        filename = os.path.basename(f)
        name_no_ext = filename[:-5]  # strip .java
        lower_name = name_no_ext.lower()

        is_test_like_name = (
            filename.endswith("Test.java") or
            filename.endswith("Tests.java") or
            filename.endswith("IT.java") or
            lower_name.startswith("test") or
            lower_name.endswith("test") or
            "test" in lower_name
        )

        # Also treat files under any directory whose name contains "test" as tests
        path_parts = f.split("/")[:-1]  # all directories
        is_under_test_dir = any("test" in part.lower() for part in path_parts)

        if not (is_test_like_name or is_under_test_dir):
            continue
            
        # Find the Maven module for this file by walking up the tree
        head = f
        module_path = ""
        while head:
            head, tail = os.path.split(head)
            if os.path.exists(os.path.join(args.repo, head, "pom.xml")):
                if head == "":
                    module_path = ""
                else:
                    module_path = head
                break
        
        # If no module found, skip
        if module_path == "":
            continue

        # Skip ignored modules
        if module_path in ["docs", "examples"]:
            continue

        # Extract class name
        class_path = None
        for marker in ["src/test/java/", "src/it/java/"]:
            if marker in f:
                class_path = f.split(marker, 1)[1]
                break

        if class_path is None:
            try:
                if module_path and f.startswith(module_path + "/"):
                    class_path = f[len(module_path) + 1:]
                else:
                    class_path = filename
            except Exception:
                continue

        try:
            class_name = class_path.replace("/", ".").replace(".java", "")
            target = f"{module_path}:{class_name}"

            if status == 'A':
                added_tests.add(target)
            else:
                modified_tests.add(target)
        except Exception:
            continue

    # 3. If FE production code changed but no explicit tests found,
    #    mark that we should run all FE tests
    if has_fe_production_changes and len(modified_tests) == 0 and len(added_tests) == 0:
        # Return a special marker for "run all fe tests"
        print(json.dumps({"modified": ["fe-core:ALL"], "added": []}))
        return

    # 4. Output JSON
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
