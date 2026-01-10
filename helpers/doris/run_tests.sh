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
    # Example: fe:org.apache.doris.FooTest be:org.apache.doris.BarTest fe-core:ALL
    
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
            # Avoid duplicates in modules list (simple check)
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
echo "--- Command: mvn test ${MAVEN_ARGS} ---"

# 2. Run Tests
# We use the same 'maven-repo' volume from the build step
docker volume create maven-repo 2>/dev/null || true

# We reuse the builder image
# We mount the repo and the maven cache
# We also create a directory for aggregated results
if docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo:/root/.m2/repository" \
    -w /repo \
    -e DORIS_HOME=/repo \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "git checkout -f ${COMMIT_SHA} && \
             POM_FILE='pom.xml'; \
             if [ -f fe/pom.xml ]; then POM_FILE='fe/pom.xml'; fi; \
             echo \"Using POM: \$POM_FILE\"; \
             mvn -f \$POM_FILE test ${MAVEN_ARGS} -DfailIfNoTests=false -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true; \
             MVN_EXIT_CODE=\$?; \
             mkdir -p /repo/build/all-test-results; \
             find . -name 'TEST-*.xml' -exec cp {} /repo/build/all-test-results/ \;; \
             exit \$MVN_EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "❌ Tests Failed"
    exit 1
fi
