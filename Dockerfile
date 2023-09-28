# --- Étape 1 : Construction de l'application Flutter ---

FROM ubuntu:20.04 AS build

# Installation des dépendances
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y curl git wget unzip libgconf-2-4 libstdc++6 libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev npm && \
    apt-get clean

# Installation de Flutter
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter doctor
RUN flutter channel master && \
    flutter upgrade && \
    flutter config --enable-web

# Installation des dépendances Node.js
RUN npm install ts-proto && \
    npm install vite@2.8 && \
    npm install -g yarn typescript protoc

# Copie du code source et construction de l'application
COPY . /app
WORKDIR /app/flutter/web/js
RUN yarn build
WORKDIR /app
RUN flutter build web


# --- Étape 2 : Configuration du serveur ---

FROM ubuntu:20.04 AS runtime

# Installation de Python3
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y python3 && \
    apt-get clean

# Copie des fichiers nécessaires depuis l'étape de build
COPY --from=build /app/build/web /app/build/web
COPY server/server.sh /app/server/

# Exposition du port et exécution du script de démarrage
EXPOSE 5000
WORKDIR /app/server
RUN chmod +x server.sh
ENTRYPOINT ["./server.sh"]
