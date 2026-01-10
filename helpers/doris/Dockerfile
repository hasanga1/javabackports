# Use the official Temurin 17 image
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        build-essential \
        gcc \
        g++ \
        cmake \
        maven \
        openjdk-17-jdk \
        python3 \
        python3-pip \
        nodejs \
        npm \
        automake \
        autoconf \
        libtool \
        bison \
        flex \
        binutils-dev \
        zip \
        unzip \
        libncurses5-dev \
        curl \
        wget \
        git \
        git-lfs \
        ninja-build \
        thrift-compiler \
        protobuf-compiler \
        && rm -rf /var/lib/apt/lists/*

# Ensure python and thrift are available under expected names
RUN if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then \
            ln -s "$(command -v python3)" /usr/local/bin/python; \
        fi && \
        if ! command -v thrift >/dev/null 2>&1 && command -v thrift-compiler >/dev/null 2>&1; then \
            ln -s "$(command -v thrift-compiler)" /usr/local/bin/thrift; \
        fi

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV MAVEN_OPTS="-Xmx4g"
ENV DORIS_BUILD_PYTHON_VERSION=python3

WORKDIR /toolkit

RUN git config --global --add safe.directory /repo && git lfs install
