#!/bin/bash
set -euo pipefail

echo "=== Building Lucene for commit ${COMMIT_SHA:0:7} ==="

# Initialize build exit code
BUILD_EXIT_CODE=0

cd "${PROJECT_DIR}"

# 1. Permission Fixes (Crucial for Gradle in Docker)
# Gradle creates lock files that often fail if user IDs don't match.
# We run a quick root container to chown everything to the current user.
echo "=== Fixing permissions and cleaning ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    --user root \
    ${BUILDER_IMAGE_TAG} \
    bash -c "git config --global --add safe.directory /repo && chown -R $(id -u):$(id -g) /repo" || true

# 2. Checkout Code
echo "=== Checking out commit ${COMMIT_SHA} ==="
git checkout -f ${COMMIT_SHA}

# 3. Create Gradle Cache Volume
docker volume create gradle-cache 2>/dev/null || true

# 4. Run Build
# We run 'assemble' and 'compileTestJava' to ensure code + tests compile.
# We skip execution of tests.
# --no-daemon is important in Docker to prevent lingering processes.
echo "=== Running Gradle Build ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "gradle-cache:/home/gradle/.gradle" \
    -w /repo \
    -e GRADLE_USER_HOME=/home/gradle/.gradle \
    ${BUILDER_IMAGE_TAG} \
    bash -c "chmod +x gradlew && ./gradlew clean compileTestJava --no-daemon --max-workers=2" \
    || BUILD_EXIT_CODE=$?

# 5. Report Status
if [ ${BUILD_EXIT_CODE} -eq 0 ]; then
    echo "Success" > "${BUILD_STATUS_FILE}"
    echo "✅ Build succeeded for ${COMMIT_SHA:0:7}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
    echo "❌ Build failed for ${COMMIT_SHA:0:7}"
fi