# syntax=docker/dockerfile:1.7

###############################################################################
# Étape 1 — Build JS/TS (RustDesk front)
###############################################################################
FROM node:20-slim AS js-build

# ————— paramètres build ——————————————
ARG RUSTDESK_REPO=MonsieurBiche/rustdesk-web-client
ARG RUSTDESK_TAG=add-features
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
        "https://github.com/${RUSTDESK_REPO}.git" rustdesk \
 && cd rustdesk \
 && git submodule update --init --recursive --depth 1

# ————— copie des sources JS ————————
WORKDIR /src/rustdesk/flutter/web
RUN if [ -d "v1" ]; then cp -a v1/* .; fi

RUN sed -i '/chunkFileNames:/a\        manualChunks(id) {\
          if (id.includes("node_modules")) return "vendor";\
        },' /src/rustdesk/flutter/web/js/vite.config.js

# --- Fix appBarActions parameter (web build) ---
RUN sed -i 's/ConnectionPage(key: _connKey);/ConnectionPage(key: _connKey, appBarActions: const <Widget>[]);/' \
    /src/rustdesk/flutter/lib/mobile/pages/home_page.dart

WORKDIR /src/rustdesk/flutter/web/js

# ————— install Yarn + deps (cache BuildKit) —
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    corepack enable && \
    corepack prepare "yarn@1.22.22" --activate && \
    yarn install --non-interactive --silent;

# ————— patch WSS éventuel —————————
RUN if [ "$ENABLE_WSS" = "true" ]; then \
      find . -name "*.ts" -o -name "*.js" | xargs sed -i 's#ws://#wss://#g'; \
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
</script>' "$HTML"


# ————— build JS ————————————————
RUN yarn build

###############################################################################
# Étape 2 — Build Flutter Web
###############################################################################
FROM debian:bookworm-slim AS flutter-build

ARG FLUTTER_VERSION=3.22.1
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

# ————— Rust + target wasm (cache BuildKit) —
RUN --mount=type=cache,target=/usr/local/cargo \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path && \
    . $HOME/.cargo/env && \
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

# 3) Dépendances web externes
RUN wget -qO /tmp/web_deps.tar.gz \
      https://github.com/pmietlicki/docker-rustdesk-web-client/raw/refs/heads/main/web_deps.tar.gz && \
    tar -xzf /tmp/web_deps.tar.gz -C web/ && \
    rm /tmp/web_deps.tar.gz

# ─── build Flutter web (stage flutter-build) ────────────────────────────────
ENV FLUTTER_ALLOW_ROOT=1
RUN --mount=type=cache,target=/usr/local/cargo \
    --mount=type=cache,target=/root/.cache/flutter \
    . $HOME/.cargo/env && \
    flutter build web --release && \
    \
    # place le bundle Vite
    mkdir -p build/web/js && \
    cp -r web/js/dist build/web/js/

###############################################################################
# Étape 3 — Runtime Nginx ultra-léger (adapté pour RustDesk Web v1)
###############################################################################
FROM nginx:alpine AS final

# ————— assets statiques —————————————
COPY --from=flutter-build /build/rustdesk/flutter/build/web /usr/share/nginx/html

RUN apk add --no-cache perl

# ————— configuration Nginx ————————————
# On utilise un placeholder HOST qu’on remplacera à l’entrée
COPY <<'EOF' /etc/nginx/conf.d/default.conf
upstream api {
    server PLACEHOLDER_HOST:21114;
}
upstream ws_id {
    server PLACEHOLDER_HOST:21118;
}
upstream ws_relay {
    server PLACEHOLDER_HOST:21119;
}
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
        add_header X-XSS-Protection "1; mode=block";
    }

    # Proxy pour l’API RustDesk
    location /api/ {
        proxy_pass PROTO://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # WebSocket pour l’ID server (port 21118) :contentReference[oaicite:0]{index=0}
    location /ws/id {
        proxy_pass PROTO://ws_id;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # WebSocket pour le relay server (port 21119) :contentReference[oaicite:1]{index=1}
    location /ws/relay {
        proxy_pass PROTO://ws_relay;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # cache long des assets
    location ~* \.(js|css|wasm|png|jpg|jpeg|gif|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# ————— entrypoint dynamique ————————
# Remplace PLACEHOLDER_HOST par la valeur de BACKEND_HOST (ou localhost par défaut)
COPY <<'EOF' /docker-entrypoint.sh
#!/bin/sh
set -e
# par défaut on pointe vers localhost
HOST="${BACKEND_HOST:-127.0.0.1}"
PROTO="${PROTO:-http}"
sed -i "s/PLACEHOLDER_HOST/$HOST/g" /etc/nginx/conf.d/default.conf
sed -i "s/PROTO/$PROTO/g" /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
EOF

RUN chmod +x /docker-entrypoint.sh

EXPOSE 80
HEALTHCHECK CMD wget -qO- http://localhost/ || exit 1
ENTRYPOINT ["/docker-entrypoint.sh"]