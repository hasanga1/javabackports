#!/bin/bash
set -e

echo "--- Building Hibernate ORM for ${COMMIT_SHA:0:7} ---"
echo "DEBUG: TOOLKIT_DIR=${TOOLKIT_DIR}"
echo "DEBUG: PROJECT_DIR=${PROJECT_DIR}"

cd "${PROJECT_DIR}"

echo "--- Checking out commit... ---"
git checkout -f ${COMMIT_SHA}
git clean -fd

# Create persistent Gradle cache volumes
docker volume create gradle-cache-hibernate 2>/dev/null || true
docker volume create gradle-wrapper-hibernate 2>/dev/null || true

echo "--- Building Docker image ---"
# Default to Java 21 for modern Hibernate, but could be adaptive if needed.
# Hibernate 6.x usually requires 11 or 17. 7.x might require 21.
# We'll stick to 21 as safer baseline for new versions.
# Default to Java 21 for modern Hibernate
JAVA_VERSION=21
IMAGE_TAG=${IMAGE_TAG_TO_BUILD:-hibernate-builder:latest}

echo "DEBUG: Image Tag=${IMAGE_TAG}"
docker build --build-arg JAVA_VERSION=${JAVA_VERSION} -t ${IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile ${TOOLKIT_DIR}

echo "--- Running Gradle build (compile only, no tests) ---"

# Fix basic layout 
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    ${IMAGE_TAG} \
    bash -c "set -e; \
             rm -rf /repo/build /repo/buildSrc/.gradle 2>/dev/null || true; \
             chmod +x gradlew 2>/dev/null || true; \
             mkdir -p /repo/.gradle /repo/build"

# Run build 
if docker run --rm \
        -v "${PROJECT_DIR}:/repo" \
        -v "gradle-cache-hibernate:/home/gradle/.gradle/caches" \
        -v "gradle-wrapper-hibernate:/home/gradle/.gradle/wrapper" \
        -w /repo \
        ${IMAGE_TAG} \
        bash -c "set -e; \
                         git config --global --add safe.directory /repo; \
                         ./gradlew cleanClasses classes testClasses -x test --no-daemon"; then
    echo "Success" > "${BUILD_STATUS_FILE}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"
