#!/bin/bash
set -euo pipefail

# Configuration
PORT=${PORT:-5000}
WEB_DIR="/app/build/web"
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

# Error handling
trap 'log "ERROR" "Server stopped unexpectedly"' ERR
trap 'log "INFO" "Received shutdown signal, stopping server..."' SIGTERM SIGINT

log "INFO" "RustDesk Web Client Server starting..."
log "INFO" "Configuration: PORT=$PORT, WEB_DIR=$WEB_DIR"

# Validate web directory exists
if [ ! -d "$WEB_DIR" ]; then
    log "ERROR" "Web directory $WEB_DIR does not exist"
    exit 1
fi

# Check if index.html exists
if [ ! -f "$WEB_DIR/index.html" ]; then
    log "WARN" "index.html not found in $WEB_DIR"
fi

# Stop any program currently running on the set port
log "INFO" "Preparing port $PORT..."
if command -v fuser >/dev/null 2>&1; then
    fuser -k ${PORT}/tcp 2>/dev/null || true
fi

# Switch to web directory
cd "$WEB_DIR" || {
    log "ERROR" "Failed to change to directory $WEB_DIR"
    exit 1
}

log "INFO" "Starting HTTP server on port $PORT"
log "INFO" "Serving files from: $(pwd)"
log "INFO" "Access the application at: http://localhost:$PORT"

# Start the server with better error handling
exec python3 -u -m http.server "$PORT" 2>&1 | while IFS= read -r line; do
    log "SERVER" "$line"
done
