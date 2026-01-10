#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

def get_module_from_path(repo_path, file_path):
    """
    Find the Maven module (directory containing pom.xml) for a file.
    For Doris, the main modules are: fe, be, tools, etc.
    Returns the shortest module path that contains a pom.xml
    """
    dir_path = os.path.dirname(file_path)
    
    # Walk up the directory tree looking for pom.xml
    while dir_path:
        pom_path = os.path.join(repo_path, dir_path, "pom.xml")
        if os.path.exists(pom_path):
            return dir_path
        
        parent = os.path.dirname(dir_path)
        if parent == dir_path:
            break
        dir_path = parent
    
    return None

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
    has_be_production_changes = False
    affected_modules = set()

    # 2. Analyze changes
    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
            
        status = parts[0]
        f = parts[1]

        if not f.endswith(".java"):
            continue

        # Track production code changes in FE and BE
        if f.startswith("fe/fe-core/src/main/java/"):
            has_fe_production_changes = True
        elif f.startswith("be/src/main/") or f.startswith("be/src/java/"):
            has_be_production_changes = True

        filename = os.path.basename(f)
        name_no_ext = filename[:-5]  # strip .java
        lower_name = name_no_ext.lower()

        # Identify test files
        is_test_like_name = (
            filename.endswith("Test.java") or
            filename.endswith("Tests.java") or
            filename.endswith("IT.java") or
            lower_name.startswith("test") or
            lower_name.endswith("test") or
            "test" in lower_name
        )

        # Check if file is under a test directory
        path_parts = f.split("/")[:-1]  # all directories
        is_under_test_dir = any(
            "test" in part.lower() 
            for part in path_parts
        )

        if not (is_test_like_name or is_under_test_dir):
            # Not a test, but track if it's production code
            module = get_module_from_path(args.repo, f)
            if module:
                affected_modules.add(module)
            continue
        
        # This is a test file
        # Find the Maven module for this file
        module = get_module_from_path(args.repo, f)
        
        # If no module found, skip
        if module is None:
            continue

        # Skip certain paths
        if module in ["docs", "examples", "docker"]:
            continue

        # Extract class name from the file path
        class_name = None
        for marker in ["src/test/java/", "src/it/java/", "src/main/java/"]:
            if marker in f:
                class_path = f.split(marker, 1)[1]
                class_name = class_path.replace("/", ".").replace(".java", "")
                break
        
        if class_name is None:
            class_name = filename[:-5]  # fallback to just filename without .java

        try:
            target = f"{module}:{class_name}"
            
            if status == 'A':
                added_tests.add(target)
            else:
                modified_tests.add(target)
        except Exception:
            continue

    # 3. If production code changed but no explicit tests found,
    #    mark that we should run all FE tests (most common case for Doris)
    if (has_fe_production_changes or has_be_production_changes) and len(modified_tests) == 0 and len(added_tests) == 0:
        # Default to running all FE tests for production changes
        if has_fe_production_changes:
            print(json.dumps({"modified": ["fe:ALL"], "added": []}))
        else:
            # For BE changes, also run FE tests as they may have integration tests
            print(json.dumps({"modified": ["fe:ALL"], "added": []}))
        return

    # 4. Output JSON
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
