#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Targets: ${TEST_TARGETS}"

GRADLE_ARGS=""
TARGET_MODULES=""

# 1. Configure Test Command
if [ "${TEST_TARGETS}" == "ALL" ]; then
    echo "--- Running ALL tests ---"
    GRADLE_ARGS="test"
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    # TEST_TARGETS is "module_path:class_name"
    # Example: lucene/core:org.apache.lucene.index.TestIndexWriter
    
    # We need to group tests by module to construct efficient Gradle commands,
    # OR construct a single command with filters.
    # Gradle syntax: ./gradlew :lucene:core:test --tests "org.apache.lucene.index.TestIndexWriter"
    
    echo "--- Parsing Granular Targets ---"
    
    # Associative array logic simulation for bash
    declare -A MODULE_TESTS
    
    for target in ${TEST_TARGETS}; do
        # Split module/class
        mod_path="${target%%:*}"   # e.g., lucene/core
        cls="${target#*:}"         # e.g., org.pkg.TestClass
        
        # Convert path to Gradle project format: lucene/core -> :lucene:core
        gradle_mod_path=$(echo ":${mod_path}" | tr '/' ':')
        
        # Append class to that module's list
        if [ -z "${MODULE_TESTS[$gradle_mod_path]}" ]; then
            MODULE_TESTS[$gradle_mod_path]="--tests \"${cls}\""
        else
            MODULE_TESTS[$gradle_mod_path]="${MODULE_TESTS[$gradle_mod_path]} --tests \"${cls}\""
        fi
        
        # Keep track of modules to iterate later
        if [[ "$TARGET_MODULES" != *"$gradle_mod_path"* ]]; then
            TARGET_MODULES="$TARGET_MODULES $gradle_mod_path"
        fi
    done
    
    # Construct the final command line
    # Format: ./gradlew :mod:test --tests "A" --tests "B" :mod2:test --tests "C"
    CMD_BUILDER=""
    for mod in $TARGET_MODULES; do
        TEST_FILTERS="${MODULE_TESTS[$mod]}"
        CMD_BUILDER="$CMD_BUILDER ${mod}:test ${TEST_FILTERS}"
    done
    
    GRADLE_ARGS="$CMD_BUILDER"
fi

echo "--- Starting Test Execution ---"
echo "--- Gradle Args: ${GRADLE_ARGS} ---"

docker volume create gradle-cache 2>/dev/null || true

# 2. Run Tests in Docker
if docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "gradle-cache:/home/gradle/.gradle" \
    -w /repo \
    -e GRADLE_USER_HOME=/home/gradle/.gradle \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "chmod +x gradlew && \
             ./gradlew ${GRADLE_ARGS} \
             --no-daemon \
             --max-workers=2 \
             -Ptests.verbose=true; \
             EXIT_CODE=\$?; \
             echo 'Collecting results...'; \
             mkdir -p /repo/all-test-results; \
             find . -name 'TEST-*.xml' -exec cp {} /repo/all-test-results/ \; 2>/dev/null || true; \
             exit \$EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "❌ Tests Failed"
    exit 1
fi