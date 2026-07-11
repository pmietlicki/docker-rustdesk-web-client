# --- Step 1: Build the Flutter application ---

FROM ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214 AS build

ARG RUSTDESK_COMMIT=f5a090c27d529a17ccfaf984c061fbf71bffd841

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 clang cmake ninja-build pkg-config libgtk-3-dev npm python3 protobuf-compiler && \
	ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Flutter
RUN git clone --branch 3.7.9 https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter doctor -v
RUN flutter config --enable-web

# Clone rustdesk repo and switch branch
RUN git clone https://github.com/pmietlicki/rustdesk-web-client.git /app/rustdesk && \
    git -C /app/rustdesk checkout --detach "$RUSTDESK_COMMIT"
WORKDIR /app/rustdesk
WORKDIR /app/rustdesk/flutter/web/js

# Add NodeSource PPA to install a newer version of Node.js
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -
RUN apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g npm@9.8.1

# Install Node.js dependencies
RUN npm install -g yarn@1.22.22 protoc@1.1.3 --force
# Update TypeScript to match newer @types/node definitions
RUN npm install ts-proto vite@2.8 yarn typescript@5.8.3 protoc --force
# Relax type checking of bundled libraries
RUN sed -i 's/"noImplicitReturns": true/&,\
    "skipLibCheck": true/' tsconfig.json

RUN yarn build

WORKDIR /app/rustdesk/flutter/web
COPY web_deps.tar.gz /tmp/web_deps.tar.gz
RUN tar xzf /tmp/web_deps.tar.gz && rm /tmp/web_deps.tar.gz

## Build the project
WORKDIR /app/rustdesk/flutter
RUN flutter build web --release


# --- Step 2: Server Configuration ---

FROM python:3.14-slim-bookworm@sha256:4ff4b92a68355dbdb52584ab3391dff8d371a61d4e063468bfd0130e3189c6d9 AS runtime

# Copy necessary files from the build stage
COPY --from=build /app/rustdesk/flutter/build/web /app/build/web
COPY v1/server/ /app/server/

# Expose the port and run the startup script
EXPOSE 5000
WORKDIR /app/server
RUN chmod 0755 server.sh generate_env_config.py && \
    useradd --uid 10001 --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin rustdesk && \
    chown -R rustdesk:rustdesk /app
USER rustdesk
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c 'import os, urllib.request; urllib.request.urlopen("http://127.0.0.1:" + os.getenv("PORT", "5000") + "/", timeout=3)' || exit 1
ENTRYPOINT ["./server.sh"]
