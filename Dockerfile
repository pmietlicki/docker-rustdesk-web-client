# syntax=docker/dockerfile:1.7

###############################################################################
# Étape 1 — Build JS/TS (RustDesk front)
###############################################################################
FROM node:25-slim@sha256:81db02c4b671288a03915da9534dbd54f96d0e7c24d80ccc54f5b36b2e684370 AS js-build

# ————— paramètres build ——————————————
ARG RUSTDESK_REPO=MonsieurBiche/rustdesk-web-client
ARG RUSTDESK_TAG=fix-build
# Un SHA explicite prime sur la branche. Le commit attendu verrouille uniquement
# la combinaison dépôt/branche par défaut et ne gêne pas les sources personnalisées.
ARG RUSTDESK_COMMIT=
ARG RUSTDESK_EXPECTED_COMMIT=525b5e561faf824850c71500adf463e4e0a504d4
ARG ENABLE_WSS=true

# ————— dépendances système minimales ————
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git python3 python-is-python3 protobuf-compiler ca-certificates \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
# ————— clone reproductible ——————————————
# ─── clone repo + sous-modules ────────────────────────────────────────────────
RUN git clone --branch "${RUSTDESK_TAG}" \
        --depth 1 \
        --recursive --shallow-submodules \
        "https://github.com/${RUSTDESK_REPO}.git" rustdesk
RUN target_commit="${RUSTDESK_COMMIT}" \
 && if [ -z "${target_commit}" ] \
      && [ "${RUSTDESK_REPO}" = "MonsieurBiche/rustdesk-web-client" ] \
      && [ "${RUSTDESK_TAG}" = "fix-build" ]; then \
      target_commit="${RUSTDESK_EXPECTED_COMMIT}"; \
    fi \
 && if [ -n "${target_commit}" ]; then \
      current_commit="$(git -C rustdesk rev-parse HEAD)"; \
      if [ "${current_commit}" != "${target_commit}" ]; then \
        git -C rustdesk fetch --depth 1 origin "${target_commit}"; \
        git -C rustdesk checkout --detach "${target_commit}"; \
      fi; \
    fi \
 && git -C rustdesk submodule update --init --recursive --depth 1

# ————— copie des sources JS ————————
WORKDIR /src/rustdesk/flutter/web
RUN if [ -d "v1" ]; then cp -a v1/* .; fi

RUN set -eu; \
    config=/src/rustdesk/flutter/web/js/vite.config.js; \
    if ! grep -q 'manualChunks(id)' "$config"; then \
      grep -q 'chunkFileNames:' "$config"; \
      sed -i '/chunkFileNames:/a\        manualChunks(id) {\
          if (id.includes("node_modules")) return "vendor";\
        },' "$config"; \
    fi; \
    grep -q 'manualChunks(id)' "$config"

# --- Fix appBarActions parameter (web build) ---
RUN set -eu; \
    source=/src/rustdesk/flutter/lib/mobile/pages/home_page.dart; \
    if grep -q 'ConnectionPage(key: _connKey);' "$source"; then \
      sed -i 's/ConnectionPage(key: _connKey);/ConnectionPage(key: _connKey, appBarActions: const <Widget>[]);/' "$source"; \
    fi; \
    grep -q 'appBarActions:' "$source"

WORKDIR /src/rustdesk/flutter/web/js

# ————— install Yarn + deps (cache BuildKit) —
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    corepack enable && \
    corepack prepare "yarn@3.2.0" --activate && \
    yarn install --immutable

# ————— patch WSS éventuel —————————
RUN if [ "$ENABLE_WSS" = "true" ]; then \
      find . -type f \( -name "*.ts" -o -name "*.js" \) \
        -exec sed -i 's#ws://#wss://#g' {} +; \
    fi

# --- RustDesk localStorage bootstrap & sanitization ---
# --- Inline <script> in index.html : full localStorage sanitization ---
RUN HTML=/src/rustdesk/flutter/web/index.html && \
    sed -i '0,/<meta charset=.UTF-8./a \
<script>\
(function(){\
  const defaults={\
    "custom-rendezvous-server":"",\
    "rendezvous-server":"",\
    "id":"",\
    "key":"",\
    "remote-id":"",\
    "peers":[],\
    "server_config":{"customServers":[]}\
  };\
  /* Balaye TOUTES les clés */\
  for(const k of Object.keys(localStorage)){\
    let v=localStorage.getItem(k);\
    if(v===null||v===""){localStorage.removeItem(k);continue;}\
    /* Si valeur JSON potentielle */\
    const f=v[0];\
    if(f==="{"||f==="["){\
      try{JSON.parse(v);}catch{localStorage.setItem(k,f==="["?"[]":"{}");}\
    }\
  }\
  /* Injecte les valeurs par défaut manquantes */\
  for(const [k,val] of Object.entries(defaults))\
    if(localStorage.getItem(k)===null)\
      localStorage.setItem(k,typeof val==="string"?val:JSON.stringify(val));\
})();\
</script>' "$HTML" && \
    grep -q 'const defaults=' "$HTML"


# ————— build JS ————————————————
RUN yarn build

###############################################################################
# Étape 2 — Build Flutter Web
###############################################################################
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df AS flutter-build

ARG FLUTTER_VERSION=3.22.1
ARG RUST_VERSION=1.97.0
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"
ENV RUSTFLAGS='--cfg getrandom_backend="js"'

# ————— dépendances système ——————————
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl git xz-utils zip unzip ca-certificates \
        build-essential clang cmake ninja-build pkg-config \
        python3 python-is-python3 protobuf-compiler \
        libgtk-3-dev libgl1-mesa-dev libglu1-mesa wget && \
    rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ————— Rust + target wasm (cache BuildKit) —
RUN --mount=type=cache,target=/usr/local/cargo \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain "${RUST_VERSION}" && \
    source "$HOME/.cargo/env" && \
    rustup target add wasm32-unknown-unknown

# ————— Flutter SDK (cache BuildKit) —————
RUN --mount=type=cache,target=/root/.cache/flutter \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git "$FLUTTER_HOME" && \
    flutter config --enable-web --no-analytics && \
    flutter precache --web

# ————— copie sources depuis js-build ————
COPY --from=js-build /src/rustdesk /build/rustdesk
WORKDIR /build/rustdesk/flutter

# 3) Dépendances web externes, versionnées avec ce dépôt
COPY web_deps.tar.gz /tmp/web_deps.tar.gz
RUN tar -xzf /tmp/web_deps.tar.gz -C web/ && \
    rm /tmp/web_deps.tar.gz

# ─── build Flutter web (stage flutter-build) ────────────────────────────────
ENV FLUTTER_ALLOW_ROOT=1
RUN --mount=type=cache,target=/usr/local/cargo \
    --mount=type=cache,target=/root/.cache/flutter \
    source "$HOME/.cargo/env" && \
    flutter build web --release && \
    \
    # place le bundle Vite
    mkdir -p build/web/js && \
    cp -r web/js/dist build/web/js/

###############################################################################
# Étape 3 — Runtime Nginx ultra-léger (adapté pour RustDesk Web v1)
###############################################################################
FROM nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752 AS final

# ————— assets statiques —————————————
COPY --from=flutter-build /build/rustdesk/flutter/build/web /usr/share/nginx/html

# ————— configuration et entrypoint Nginx ————————————
COPY docker/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY docker/nginx/entrypoint.sh /docker-entrypoint.sh
RUN chmod 0755 /docker-entrypoint.sh

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/docker-entrypoint.sh"]
