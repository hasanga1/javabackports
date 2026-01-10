# Apache Lucene 10.x requires JDK 21
FROM eclipse-temurin:21-jdk

# ---- system packages --------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    curl \
    unzip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# ---- Boot JDK setup -------------------------------------------------
# Gradle usually handles the JDK via toolchains, but we set JAVA_HOME just in case
ENV BOOT_JDK=/opt/java/openjdk
RUN echo "Boot JDK is at ${BOOT_JDK}" && ${BOOT_JDK}/bin/java -version

# --- Switch to root user to fix all permission errors ---
WORKDIR /repo

# Add the repo directory as a "safe directory" for Git
RUN git config --global --add safe.directory /repo

# ---- Git LFS setup ----------------------------------------------------
RUN git lfs install --system