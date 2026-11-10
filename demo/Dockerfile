# Demo de reconhecimento facial (página estática + MediaPipe Face Landmarker).
# Os arquivos do MediaPipe e o modelo são baixados no build e servidos localmente,
# então a página funciona sem internet depois de construída.
FROM node:20-alpine AS assets
ARG MP_VERSION=0.10.14
ARG GIFENC_VERSION=1.0.3
WORKDIR /build
RUN npm pack @mediapipe/tasks-vision@${MP_VERSION} \
 && tar xzf mediapipe-tasks-vision-${MP_VERSION}.tgz \
 && mkdir -p vendor \
 && cp package/vision_bundle.mjs vendor/ \
 && cp -r package/wasm vendor/wasm
# encoder de GIF usado pelo botão "GIF 5s" (roda no navegador)
RUN npm pack gifenc@${GIFENC_VERSION} \
 && mkdir gifenc && tar xzf gifenc-${GIFENC_VERSION}.tgz -C gifenc \
 && cp gifenc/package/dist/gifenc.esm.js vendor/gifenc.esm.js
ADD https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task vendor/face_landmarker.task
# ADD de URL grava o arquivo com permissão 600; o nginx (usuário nginx) precisa ler
RUN chmod -R a+rX vendor

FROM nginx:1.27-alpine
# HTTPS (porta 443) com certificado autoassinado: o celular só libera a câmera em HTTPS
RUN apk add --no-cache openssl
COPY gen-cert.sh /docker-entrypoint.d/05-gen-cert.sh
RUN sed -i 's/\r$//' /docker-entrypoint.d/05-gen-cert.sh && chmod +x /docker-entrypoint.d/05-gen-cert.sh
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site.inc /etc/nginx/conf.d/demo-site.inc
COPY index.html /usr/share/nginx/html/index.html
COPY --from=assets /build/vendor /usr/share/nginx/html/vendor
