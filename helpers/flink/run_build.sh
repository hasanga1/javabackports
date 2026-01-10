#!/bin/bash
# Build Flink using Maven inside the pre-built builder image
set -e

echo "--- Building Flink for commit ${COMMIT_SHA:0:7} ---"

echo "--- Changing directory to ${PROJECT_DIR} ---"
cd "${PROJECT_DIR}"

echo "--- Checking out commit... ---"
git checkout -f ${COMMIT_SHA}

# Create persistent Maven cache volume
docker volume create maven-cache-flink 2>/dev/null || true

echo "--- Running Maven build (compile only, no tests, skipping flink-runtime-web) ---"

# Skip the flink-runtime-web module to avoid frontend (npm) build failures.
# We still build all required dependencies via -am.
BUILD_COMMAND="mvn -pl '!flink-runtime-web' -am clean install -DskipTests \
  -Dmaven.javadoc.skip=true \
  -Dcheckstyle.skip=true \
  -Dspotbugs.skip=true \
  -Denforcer.skip=true"

if docker run --rm \
    --dns=8.8.8.8 \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-cache-flink:/root/.m2" \
    -w /repo \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "rm -rf /root/.m2/repository/org/apache/flink && ${BUILD_COMMAND}"; then
    echo "Success" > "${BUILD_STATUS_FILE}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"
