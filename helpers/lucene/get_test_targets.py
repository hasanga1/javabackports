#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

def find_gradle_module(repo, filepath):
    """
    Find the directory containing build.gradle for a given file.
    Returns the path relative to the repo root.
    """
    current_dir = os.path.dirname(filepath) if filepath else ""
    
    while current_dir:
        # Check for build.gradle or build.gradle.kts
        if os.path.exists(os.path.join(repo, current_dir, "build.gradle")) or \
           os.path.exists(os.path.join(repo, current_dir, "build.gradle.kts")):
            return current_dir
        
        parent = os.path.dirname(current_dir)
        if parent == current_dir or parent == "":
            break
        current_dir = parent
    
    return None

def extract_test_class(filepath):
    """Extract the fully qualified test class name from a test file path."""
    # Lucene structure is usually src/test/org/apache/lucene/...
    # But sometimes src/test/java/org/...
    
    prefixes = ["/src/test/java/", "/src/test/"]
    
    for prefix in prefixes:
        if prefix in filepath:
            try:
                class_part = filepath.split(prefix)[1]
                # Remove .java
                if class_part.endswith(".java"):
                    class_part = class_part[:-5]
                
                class_name = class_part.replace("/", ".")
                return class_name
            except:
                continue
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

    for line in output.strip().splitlines():
        parts = line.split('\t')
        if not parts:
            continue
            
        status = parts[0]
        
        # Handle Renames (R) and Copies (C)
        if status.startswith('R') or status.startswith('C'):
            if len(parts) >= 3:
                filepath = parts[2]
            else:
                continue
        else:
            if len(parts) >= 2:
                filepath = parts[1]
            else:
                continue
        
        filename = os.path.basename(filepath)
        
        # Filter for Java Test files
        # Lucene tests usually end with Test.java or start with Test
        is_test_file = (
            filepath.endswith(".java") and
            ("/src/test/" in filepath) and 
            (filename.startswith("Test") or filename.endswith("Test.java"))
        )
        
        if not is_test_file:
            continue
            
        # Find module (directory having build.gradle)
        module = find_gradle_module(args.repo, filepath)
        if not module:
            continue
        
        # Extract test class name
        test_class = extract_test_class(filepath)
        if not test_class:
            continue
        
        # Target format: module_path:fully.qualified.Class
        # Example: lucene/core:org.apache.lucene.index.TestIndexWriter
        target = f"{module}:{test_class}"
        
        if status == 'A':
            added_tests.add(target)
        else:
            modified_tests.add(target)
    
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    
    print(json.dumps(result))

if __name__ == "__main__":
    main()