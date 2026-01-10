#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

# Modules known to be problematic or requiring complex environments
BLACKLIST_MODULES = [
    "hive-packaging",
    "hive-assembly",
]

def is_blacklisted(module_path):
    for bad in BLACKLIST_MODULES:
        if module_path == bad or module_path.startswith(bad + "/"):
            return True
    return False

def find_module_for_file(repo, filepath):
    """Find the Maven module (directory with pom.xml) for a given file."""
    current_dir = os.path.dirname(filepath) if filepath else ""
    
    while current_dir:
        pom_path = os.path.join(repo, current_dir, "pom.xml")
        if os.path.exists(pom_path):
            if not is_blacklisted(current_dir):
                return current_dir
            else:
                return None  # Blacklisted module
        parent = os.path.dirname(current_dir)
        if parent == current_dir:
            break
        current_dir = parent
    
    return None

def extract_test_class(filepath):
    """Extract the fully qualified test class name from a test file path."""
    if "/src/test/java/" not in filepath:
        return None
    
    try:
        class_part = filepath.split("/src/test/java/")[1]
        class_name = class_part.replace("/", ".").replace(".java", "")
        return class_name
    except:
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

    # 2. Process changed files
    modified_modules = set()
    modified_test_modules = set()
    added_test_modules = set()

    for line in output.strip().split('\n'):
        if not line.strip():
            continue
        
        parts = line.split(None, 1)
        status = parts[0]
        filepath = parts[1] if len(parts) > 1 else ""
        
        if not filepath.endswith(".java"):
            continue
        
        # Check if it's a test file
        is_test_file = "/src/test/java/" in filepath
        
        # Find the Maven module
        module = find_module_for_file(args.repo, filepath)


        # Map itests subdirectories to their Maven modules
        # Only map to modules that exist in pom.xml
        valid_modules = set([
            "hcatalog", "qtest", "qtest-accumulo", "qtest-spark", "hive-jmh", "hive-minikdc"
        ])
        itests_module_map = {
            "itests/hcatalog-unit": "hcatalog",
            "itests/qtest": "qtest",
            "itests/qtest-accumulo": "qtest-accumulo",
            "itests/qtest-spark": "qtest-spark",
            "itests/hive-jmh": "hive-jmh",
            "itests/hive-minikdc": "hive-minikdc"
        }
        for test_path, mod_name in itests_module_map.items():
            if test_path in filepath and mod_name in valid_modules:
                module = mod_name
                break

        if not module:
            continue

        if is_test_file:
            test_class = extract_test_class(filepath)
            if test_class:
                if status == "A":  # Added
                    added_test_modules.add(f"{module}:{test_class}")
                else:  # Modified
                    modified_test_modules.add(f"{module}:{test_class}")
        else:
            # Production code change - need to test this module
            modified_modules.add(module)

    # 3. Output JSON
    output_data = {
        "modified": list(modified_test_modules),
        "added": list(added_test_modules)
    }
    
    print(json.dumps(output_data))

if __name__ == "__main__":
    main()
