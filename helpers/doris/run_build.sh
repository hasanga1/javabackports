#!/bin/bash
# Doris build script: delegate to official build.sh
set -euo pipefail

echo "=== Building Doris for commit ${COMMIT_SHA:0:7} ==="

BUILD_EXIT_CODE=0

cd "${PROJECT_DIR}"

# Clean Docker-created files and fix permissions
echo "=== Cleaning and fixing permissions ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    --user root \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "git config --global --add safe.directory /repo && git clean -fdx && chown -R $(id -u):$(id -g) /repo" || true

# Checkout the commit
echo "=== Checking out commit ${COMMIT_SHA} ==="
git checkout -f "${COMMIT_SHA}"

# Create reusable volume caches
docker volume create maven-repo-doris 2>/dev/null || true
docker volume create doris-thirdparty 2>/dev/null || true

echo "=== Building with Doris build.sh ==="

# Determine build flags based on changed files
# Default to FE-only build for performance
BUILD_FLAGS="--fe"
if [ "${DORIS_BUILD_SCOPE:-FE_ONLY}" = "FULL" ]; then
    echo "--- Full build (FE + BE + UI) ---"
    BUILD_FLAGS=""
else
    echo "--- Frontend-only build (FE) ---"
fi

# Run build.sh inside container with proper environment
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo-doris:/root/.m2/repository" \
    -v "doris-thirdparty:/tmp/doris_thirdparty" \
    -w /repo \
    -e DORIS_HOME=/repo \
    -e DORIS_THIRDPARTY=/tmp/doris_thirdparty \
    --cpus=4 \
    --memory=8g \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "set -x && \
             git config --global --add safe.directory /repo && \
             git checkout -f ${COMMIT_SHA} && \
             git submodule update --init --recursive 2>/dev/null || true && \
             bash build.sh --clean ${BUILD_FLAGS} 2>&1" || BUILD_EXIT_CODE=$?

if [ "${BUILD_EXIT_CODE}" -eq 0 ]; then
    echo "Success" > "${BUILD_STATUS_FILE}"
    echo "✅ Build succeeded for ${COMMIT_SHA:0:7}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
    echo "❌ Build failed for ${COMMIT_SHA:0:7} (exit code ${BUILD_EXIT_CODE})"
fi

echo "=== Build finished for ${COMMIT_SHA:0:7} ==="
