#!/usr/bin/env bash

PORT=5000
echo "preparing port $PORT…"
fuser -k $PORT/tcp

cd /app/build/web/

cat > env-config.js <<EOF
// ce script est exécuté avant le main.js de ton app
window.localStorage.setItem("custom-rendezvous-server", "${CUSTOM_RENDEZVOUS_SERVER:-}");
window.localStorage.setItem("relay-server",             "${RELAY_SERVER:-}");
window.localStorage.setItem("api-server",               "${API_SERVER:-}");
window.localStorage.setItem("key",                      "${KEY:-}");
EOF

if ! grep -q "env-config.js" index.html; then
  sed -i 's|</head>|  <script src="env-config.js"></script>\n</head>|' index.html
fi

echo "Server starting on port $PORT…"
python3 -m http.server $PORT
