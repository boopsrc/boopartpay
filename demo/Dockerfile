# Demo de reconhecimento facial (página estática + MediaPipe Face Landmarker).
# Os arquivos do MediaPipe e o modelo são baixados no build e servidos localmente,
# então a página funciona sem internet depois de construída.
FROM node:20-alpine AS assets
ARG MP_VERSION=0.10.14
WORKDIR /build
RUN npm pack @mediapipe/tasks-vision@${MP_VERSION} \
 && tar xzf mediapipe-tasks-vision-${MP_VERSION}.tgz \
 && mkdir -p vendor \
 && cp package/vision_bundle.mjs vendor/ \
 && cp -r package/wasm vendor/wasm
ADD https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task vendor/face_landmarker.task

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY --from=assets /build/vendor /usr/share/nginx/html/vendor
