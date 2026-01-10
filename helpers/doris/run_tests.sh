#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Targets: ${TEST_TARGETS}"

# 1. Configure Test Command
if [ "${TEST_TARGETS}" == "ALL" ]; then
    # Run standard unit tests for everything
    MAVEN_ARGS=""
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    # TEST_TARGETS is a space-separated list of "module:class" or special markers like "fe-core:ALL"
    # Example: fe-core:org.apache.doris.FooTest be-core:org.apache.doris.BarTest fe-core:ALL
    
    MODULES=""
    TESTS=""
    RUN_ALL_IN_MODULE=""
    
    # Split by space
    for target in ${TEST_TARGETS}; do
        # Split by colon
        mod="${target%%:*}"
        cls="${target#*:}"
        
        # Check if this is a special "run all tests in module" marker
        if [ "${cls}" == "ALL" ]; then
            # Add this module and run all tests in it
            if [ -z "$RUN_ALL_IN_MODULE" ]; then
                RUN_ALL_IN_MODULE="$mod"
            else
                RUN_ALL_IN_MODULE="$RUN_ALL_IN_MODULE,$mod"
            fi
            continue
        fi
        
        # Append to lists (comma separated)
        if [ -z "$MODULES" ]; then
            MODULES="$mod"
        else
            # Avoid duplicates in modules list
            if [[ ",$MODULES," != *",$mod,"* ]]; then
                MODULES="$MODULES,$mod"
            fi
        fi
        
        if [ -z "$TESTS" ]; then
            TESTS="$cls"
        else
            TESTS="$TESTS,$cls"
        fi
    done
    
    # Build MAVEN_ARGS
    if [ -n "$RUN_ALL_IN_MODULE" ]; then
        # Run all tests in these modules
        MAVEN_ARGS="-pl ${RUN_ALL_IN_MODULE}"
    elif [ -n "$MODULES" ]; then
        MAVEN_ARGS="-pl ${MODULES} -Dtest=${TESTS}"
    fi
fi

echo "--- Starting Test Execution ---"
echo "--- Maven Args: ${MAVEN_ARGS} ---"

# 2. Run Tests with reusable volume caches
docker volume create maven-repo-doris 2>/dev/null || true

# Use the builder image to run tests
# Mount the repo and maven cache
# Collect results into a standard location
if docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo-doris:/root/.m2/repository" \
    -w /repo \
    -e DORIS_HOME=/repo \
    -e JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
    --cpus=4 \
    --memory=8g \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "git config --global --add safe.directory /repo && \
             git checkout -f ${COMMIT_SHA} && \
             cd fe && \
             mvn test ${MAVEN_ARGS} \
               -DfailIfNoTests=false \
               -Dmaven.javadoc.skip=true \
               -Dcheckstyle.skip=true \
               -Dmaven.test.skip=false \
               -Dorg.slf4j.simpleLogger.defaultLogLevel=info; \
             MVN_EXIT_CODE=\$?; \
             mkdir -p /repo/build/all-test-results; \
             find . -path '*/target/surefire-reports/TEST-*.xml' -exec cp {} /repo/build/all-test-results/ \;; \
             exit \$MVN_EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "⚠️  Tests Completed (with failures)"
    # Still collect the results even if tests fail
    exit 0
fi
