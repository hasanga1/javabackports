#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Targets: ${TEST_TARGETS}"

if [ "${TEST_TARGETS}" == "ALL" ]; then
    MAVEN_ARGS=""
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    MODULES=""
    TESTS=""
    for target in ${TEST_TARGETS}; do
        mod="${target%%:*}"
        cls="${target#*:}"
        if [ -z "$MODULES" ]; then
            MODULES="$mod"
        else
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
    MAVEN_ARGS="-pl $MODULES -Dtest=$TESTS"
fi

docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo:/root/.m2/repository" \
    -w /repo \
    ${BUILDER_IMAGE_TAG} \
    bash -c "mvn test $MAVEN_ARGS -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C"
