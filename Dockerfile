# --- Étape 1 : Construction de l'application Flutter ---

FROM ubuntu:20.04 AS build

# Installation des dépendances
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 clang cmake ninja-build pkg-config libgtk-3-dev npm python3 protobuf-compiler && \
	ln -s /usr/bin/python3 /usr/bin/python && \
    apt-get clean

# Installation de Flutter
RUN git clone --branch 3.7.9 https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter doctor -v
RUN flutter config --enable-web

# Clonage du dépôt rustdesk et changement de branche
RUN git clone https://github.com/JelleBuning/rustdesk_web.git /app/rustdesk
RUN git switch fix_build
WORKDIR /app/rustdesk/flutter/web/js

# Ajout du PPA NodeSource pour installer une version plus récente de Node.js
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -
RUN apt-get install -y nodejs

RUN npm install -g npm@9.8.1

# Installation des dépendances Node.js
RUN npm install ts-proto vite@2.8 yarn typescript protoc

RUN yarn build

WORKDIR /app/rustdesk/flutter/web
RUN wget https://github.com/rustdesk/doc.rustdesk.com/releases/download/console/web_deps.tar.gz
RUN tar xzf web_deps.tar.gz

## Construction du projet
WORKDIR /app/rustdesk/flutter
RUN flutter build web --release


# --- Étape 2 : Configuration du serveur ---

FROM ubuntu:20.04 AS runtime

# Installation de Python3
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y python3 && \
    apt-get clean

# Copie des fichiers nécessaires depuis l'étape de build
COPY --from=build /app/rustdesk/build/web /app/build/web
COPY server/server.sh /app/server/

# Exposition du port et exécution du script de démarrage
EXPOSE 5000
WORKDIR /app/server
RUN chmod +x server.sh
ENTRYPOINT ["./server.sh"]
