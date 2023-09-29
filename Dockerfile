# --- Step 1: Build the Flutter application ---

FROM ubuntu:20.04 AS build

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 clang cmake ninja-build pkg-config libgtk-3-dev npm python3 protobuf-compiler && \
	ln -s /usr/bin/python3 /usr/bin/python && \
    apt-get clean

# Install Flutter
RUN git clone --branch 3.7.9 https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter doctor -v
RUN flutter config --enable-web

# Clone rustdesk repo and switch branch
RUN git clone https://github.com/JelleBuning/rustdesk.git /app/rustdesk
WORKDIR /app/rustdesk
RUN git switch fix_build
WORKDIR /app/rustdesk/flutter/web/js

# Add NodeSource PPA to install a newer version of Node.js
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -
RUN apt-get install -y nodejs

RUN npm install -g npm@9.8.1

# Install Node.js dependencies
RUN npm install -g yarn typescript protoc --force
RUN npm install ts-proto vite@2.8 yarn typescript protoc --force

RUN yarn build

WORKDIR /app/rustdesk/flutter/web
RUN wget https://github.com/rustdesk/doc.rustdesk.com/releases/download/console/web_deps.tar.gz
RUN tar xzf web_deps.tar.gz

## Build the project
WORKDIR /app/rustdesk/flutter
RUN flutter build web --release


# --- Step 2: Server Configuration ---

FROM ubuntu:20.04 AS runtime

# Install Python3
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y python3 psmisc && \
    apt-get clean

# Copy necessary files from the build stage
COPY --from=build /app/rustdesk/flutter/build/web /app/build/web
COPY server/server.sh /app/server/

# Expose the port and run the startup script
EXPOSE 5000
WORKDIR /app/server
RUN chmod +x server.sh
ENTRYPOINT ["./server.sh"]
