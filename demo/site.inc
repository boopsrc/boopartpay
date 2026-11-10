# Conteúdo servido igual em HTTP e HTTPS (incluído pelo nginx.conf).
root /usr/share/nginx/html;
index index.html;

location ~ \.mjs$ { default_type application/javascript; }
location ~ \.wasm$ { default_type application/wasm; }
location ~ \.task$ { default_type application/octet-stream; }
location = /favicon.ico { access_log off; log_not_found off; return 204; }
