#!/bin/bash
# Build script for grpc project
set -euo pipefail

echo "=== Building grpc for commit ${COMMIT_SHA:0:7} ==="

BUILD_EXIT_CODE=0

cd "${PROJECT_DIR}"

echo "=== Cleaning Docker-created files and fixing permissions ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    --user root \
    ${BUILDER_IMAGE_TAG} \
    bash -c "git config --global --add safe.directory /repo && git clean -fdx && chown -R $(id -u):$(id -g) /repo" || true

echo "=== Checking out commit ${COMMIT_SHA} ==="
git checkout -f ${COMMIT_SHA}

docker volume create maven-repo 2>/dev/null || true

echo "=== Running standard Maven build ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo:/root/.m2/repository" \
    -w /repo \
    ${BUILDER_IMAGE_TAG} \
    bash -c "mvn clean install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C" \
    || BUILD_EXIT_CODE=$?

exit $BUILD_EXIT_CODE
