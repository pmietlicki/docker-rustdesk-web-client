# RustDesk Web Client - Dockerfile basé sur MonsieurBiche/rustdesk-web-client
# Version améliorée avec Debian Bullseye et configuration flexible

# ===== Stage 1: Base Environment =====
FROM debian:bullseye-slim AS base

WORKDIR /
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && \
    apt-get install --yes --no-install-recommends \
        g++ \
        gcc \
        git \
        curl \
        nasm \
        yasm \
        libgtk-3-dev \
        clang \
        libxcb-randr0-dev \
        libxdo-dev \
        libxfixes-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libasound2-dev \
        libpam0g-dev \
        libpulse-dev \
        make \
        cmake \
        unzip \
        zip \
        sudo \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        ca-certificates \
        ninja-build && \
        rm -rf /var/lib/apt/lists/*

RUN git clone --branch 2023.04.15 --depth=1 https://github.com/microsoft/vcpkg && \
    /vcpkg/bootstrap-vcpkg.sh -disableMetrics && \
    /vcpkg/vcpkg --disable-metrics install libvpx libyuv opus aom

# Create user for security (adapted for our constraints)
RUN useradd -m -s /bin/bash user
WORKDIR /home/user
RUN curl -LO https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so

# Install Rust and configure environment for user
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup.sh && \
    chmod +x rustup.sh && \
    ./rustup.sh -y && \
    mkdir -p /home/user/.cargo && \
    cp -r /root/.cargo/* /home/user/.cargo/ && \
    cp -r /root/.rustup   /home/user/.rustup && \
    chown -R user:user /home/user/.cargo && \
    chown -R user:user /home/user/.rustup && \
    echo 'source /home/user/.cargo/env' >> /home/user/.bashrc

ENV HOME=/home/user
ENV PATH="/home/user/.cargo/bin:/root/.cargo/bin:$PATH"

# ===== Stage 2: Build Environment =====
FROM base AS build-env

# Arguments de configuration flexible
ARG FLUTTER_VERSION=3.22.1
ARG RUSTDESK_BRANCH=enable-wss
ARG RUSTDESK_REPO=MonsieurBiche/rustdesk-web-client
ARG ENABLE_WSS=true

# Install dependencies using package manager (excluding cargo since we use rustup)
RUN apt-get update && \
    apt-get install -y build-essential pkg-config zip unzip wget curl git nasm && \
    apt-get install -y cmake python3-clang libgtk-3-dev && \
    apt-get install -y curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 clang cmake ninja-build pkg-config libgtk-3-dev npm python3 protobuf-compiler && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    apt-get clean

# Install vcpkg (version optimisée selon la nouvelle approche)
ENV VCPKG_ROOT=/opt/vcpkg
RUN wget -qO vcpkg.tar.gz https://github.com/microsoft/vcpkg/archive/master.tar.gz && \
    mkdir $VCPKG_ROOT && \
    tar xf vcpkg.tar.gz --strip-components=1 -C $VCPKG_ROOT && \
    $VCPKG_ROOT/bootstrap-vcpkg.sh && \
    ln -s $VCPKG_ROOT/vcpkg /usr/local/bin/vcpkg && \
    rm -rf vcpkg.tar.gz

# Install dependencies using vcpkg
RUN export VCPKG_ROOT=$VCPKG_ROOT && \
    vcpkg install libvpx libyuv opus aom

# Install Flutter with version flexible
ARG FLUTTER_SDK=/usr/local/flutter
RUN git clone https://github.com/flutter/flutter.git $FLUTTER_SDK && \
    cd $FLUTTER_SDK && git fetch && git checkout $FLUTTER_VERSION
RUN chown -R user:user ${FLUTTER_SDK} && \
    git config --global --add safe.directory ${FLUTTER_SDK}
ENV PATH="$FLUTTER_SDK/bin:$FLUTTER_SDK/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter doctor -v && \
    flutter config --enable-web --no-analytics && \
    flutter precache --web

# Prepare container
ARG APP=/app
RUN mkdir -p $APP

# Clone RustDesk repository with flexible configuration
WORKDIR $APP
RUN echo "Cloning RustDesk from $RUSTDESK_REPO with branch: $RUSTDESK_BRANCH" && \
    git clone --depth=1 --branch "$RUSTDESK_BRANCH" \
      https://github.com/$RUSTDESK_REPO.git rustdesk && \
    echo "Successfully cloned $RUSTDESK_REPO ($RUSTDESK_BRANCH branch)" && \
    ls -la $APP/rustdesk

# ===== Web JS Build =====
WORKDIR $APP/rustdesk/flutter/web/js

# Files are now split into v1 and v2, v2 not public, need to copy to web folder to have correct paths in scripts
RUN cp -R ../v1/* ../

# Add NodeSource PPA to install a newer version of Node.js
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -

# Pin nodejs repo for stability
RUN printf 'Package: nodejs\nPin: origin deb.nodesource.com\nPin-Priority: 600' > /etc/apt/preferences.d/nodesource

RUN apt-get install -y nodejs

RUN npm install -g npm@9.8.1

# Install Node.js dependencies
RUN npm install -g yarn typescript protoc --force && \
    npm install ts-proto vite@2.8 yarn typescript protoc --force && \
    npm install typescript@latest

RUN yarn build

# ===== Web deps =====
WORKDIR $APP/rustdesk/flutter/web
RUN wget https://github.com/pmietlicki/docker-rustdesk-web-client/raw/refs/heads/main/web_deps.tar.gz && \
    tar xzf web_deps.tar.gz

# ===== Build Web app =====
WORKDIR $APP/rustdesk/flutter

# Vérification de l'environnement Flutter
RUN echo "Checking Flutter environment..." && \
    ls -la . && \
    cat pubspec.yaml | head -20 && \
    echo "pubspec.yaml found and readable"

# Nettoyage et réparation du cache avec gestion d'erreurs
RUN flutter pub cache clean && \
    flutter pub cache repair

# Récupération des dépendances avec retry
RUN flutter clean || true && \
    flutter doctor -v && \
    (flutter pub get --verbose || (echo "Première tentative échouée, retry..." && sleep 5 && flutter pub get --verbose)) && \
    (flutter pub deps || echo "Warning: flutter pub deps failed but continuing...")

# Switch to user context and build optimisé avec gestion d'erreurs
RUN chown -R user:user /home/user /app /usr/local/flutter
USER user
RUN ./run.sh build web --release --verbose
USER root

# ===== Stage 3: Runtime Container =====
FROM ubuntu:20.04 AS runtime

# Install Python3 and dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y python3 psmisc curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy necessary files from the build stage
COPY --from=build-env /app/rustdesk/flutter/build/web /app/build/web

# Copy server script from host
COPY server/server.sh /app/server/server.sh
RUN chmod +x /app/server/server.sh

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/ || exit 1

# Set environment variables for better logging
ENV PYTHONUNBUFFERED=1
ENV PORT=5000

# Expose the port
EXPOSE 5000
WORKDIR /app/server
ENTRYPOINT ["./server.sh"]
