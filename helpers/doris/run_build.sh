#!/bin/bash
# Doris build script aligned with official build.sh & thirdparty flow
set -euo pipefail

echo "=== Building Doris for commit ${COMMIT_SHA:0:7} ==="

BUILD_EXIT_CODE=0

cd "${PROJECT_DIR}"

echo "=== Cleaning Docker-created files and fixing permissions ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    --user root \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "git config --global --add safe.directory /repo && git clean -fdx && chown -R $(id -u):$(id -g) /repo" || true

echo "=== Checking out commit ${COMMIT_SHA} ==="
git checkout -f "${COMMIT_SHA}"

# Reusable caches: Maven repo and Doris thirdparty
docker volume create maven-repo-doris 2>/dev/null || true
docker volume create doris-thirdparty 2>/dev/null || true

echo "=== Running Doris build inside builder container ==="

docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo-doris:/root/.m2/repository" \
    -v "doris-thirdparty:/repo/thirdparty/installed" \
    -w /repo \
    -e DORIS_HOME=/repo \
    "${BUILDER_IMAGE_TAG}" \
    bash -c '
        set -euo pipefail
        echo "--- In Doris builder container ---"
        ls -la

        if [ -f env.sh ]; then
            echo "Preparing Doris env vars and sourcing env.sh ..."
            if [ -z "${DORIS_HOME:-}" ]; then
                export DORIS_HOME=/repo
            fi
            if [ -z "${DORIS_THIRDPARTY:-}" ]; then
                if [ -d /repo/thirdparty/installed ]; then
                    export DORIS_THIRDPARTY=/repo/thirdparty/installed
                elif [ -d /repo/thirdparty ]; then
                    export DORIS_THIRDPARTY=/repo/thirdparty
                fi
            fi
            . ./env.sh
        else
            echo "env.sh NOT found; continuing without it"
        fi

        if [ -d thirdparty ]; then
            if [ ! -f thirdparty/installed/.thirdparty_built ]; then
                echo "=== Building Doris thirdparty dependencies (one-time, may take long) ==="
                cd thirdparty
                if [ -f build-thirdparty.sh ]; then
                    bash build-thirdparty.sh
                else
                    echo "build-thirdparty.sh not found; skipping explicit thirdparty build"
                fi
                cd /repo
                mkdir -p thirdparty/installed
                touch thirdparty/installed/.thirdparty_built || true
            else
                echo "Using cached thirdparty in thirdparty/installed"
            fi
        else
            echo "thirdparty directory not present; skipping thirdparty build"
        fi

        if [ -f build.sh ]; then
            SCOPE="${DORIS_BUILD_SCOPE:-FE_ONLY}"
            echo "=== Detected Doris build.sh; scope=${SCOPE} ==="
            if [ "${SCOPE}" = "FULL" ]; then
                echo "Running full Doris build (FE + BE + UI) via build.sh"
                bash build.sh || exit $?
            else
                echo "Running Doris frontend-only build via build.sh --fe"
                bash build.sh --fe || exit $?
            fi
        else
            echo "build.sh NOT found; falling back to direct Maven build"

            if [ -f generated-source.sh ]; then
                echo "Found generated-source.sh; generating sources ..."
                thrift --version || echo "Thrift not found in PATH"
                bash generated-source.sh noclean || echo "generated-source.sh failed (continuing)"
            fi

            if [ -f fe/pom.xml ]; then
                echo "Using fe/pom.xml for Maven build"
                mvn -f fe/pom.xml clean install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Dforbiddenapis.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C
            else
                echo "No fe/pom.xml found, running Maven from repo root"
                mvn clean install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Dforbiddenapis.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C
            fi
        fi
    ' || BUILD_EXIT_CODE=$?

if [ "${BUILD_EXIT_CODE}" -eq 0 ]; then
    echo "Success" > "${BUILD_STATUS_FILE}"
    echo "✅ Build succeeded for ${COMMIT_SHA:0:7}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
    echo "❌ Build failed for ${COMMIT_SHA:0:7} (exit code ${BUILD_EXIT_CODE})"
fi

echo "=== Build finished for ${COMMIT_SHA:0:7} ==="
