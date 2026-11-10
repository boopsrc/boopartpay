#!/bin/sh
# Gera um certificado autoassinado na primeira subida do container (rodado pelo
# entrypoint do nginx). Fica num volume, então o celular só avisa uma vez.
set -e
dir=/etc/nginx/certs
if [ -s "$dir/demo.crt" ] && [ -s "$dir/demo.key" ]; then exit 0; fi
mkdir -p "$dir"
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=boopdemo" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -keyout "$dir/demo.key" -out "$dir/demo.crt" >/dev/null 2>&1
echo "gen-cert: certificado autoassinado criado em $dir"
