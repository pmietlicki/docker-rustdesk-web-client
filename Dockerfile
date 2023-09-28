# Install operating system and dependencies
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get install -y curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback lib32stdc++6 python3 clang cmake ninja-build pkg-config libgtk-3-dev
RUN apt-get clean

# Download Flutter SDK from Flutter GitHub repo
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter

# Set flutter environment path
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Run flutter doctor
RUN flutter doctor

# Enable flutter web
RUN flutter channel master
RUN flutter upgrade
RUN flutter config --enable-web

# Copy files to container and build
RUN mkdir /app/
# I was unable to build web app from dockerfile
# So instead I built it locally and commented the "flutter build web" in this file
COPY . /app/
WORKDIR /app/
# RUN flutter build web

# Record the exposed port
EXPOSE 5000

# Make server startup script executable and start the web server
RUN ["chmod", "+x", "/app/server/server.sh"]

ENTRYPOINT [ "/app/server/server.sh"]
