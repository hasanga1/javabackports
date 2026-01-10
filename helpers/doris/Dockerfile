# Use Apache Doris's recommended build environment
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies required for building Doris
RUN apt-get update && apt-get install -y \
        build-essential \
        gcc-9 \
        g++-9 \
        cmake \
        ccache \
        maven \
        openjdk-8-jdk \
        openjdk-17-jdk \
        python3 \
        python3-pip \
        python3-dev \
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
        libssl-dev \
        curl \
        wget \
        git \
        git-lfs \
        ninja-build \
        thrift-compiler \
        protobuf-compiler \
        gdb \
        telnet \
        mysql-client \
        libboost-all-dev \
        libffi-dev \
        pkg-config \
        && rm -rf /var/lib/apt/lists/*

# Set up Java and environment
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV JDK_17=/usr/lib/jvm/java-17-openjdk-amd64
ENV MAVEN_OPTS="-Xmx8g"
ENV DORIS_THIRDPARTY=/tmp/doris_thirdparty
ENV PYTHON_EXECUTABLE=/usr/bin/python3

# Create directories for dependencies
RUN mkdir -p /root/.m2/repository && \
    mkdir -p ${DORIS_THIRDPARTY}

# Configure git
RUN git config --global --add safe.directory /repo && \
    git lfs install

WORKDIR /toolkit
