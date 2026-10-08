# ---- build stage: Node toolchain, thrown away after `vite build`
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

# ---- runtime stage: unprivileged nginx (runs as uid 101, listens on 8080)
FROM nginxinc/nginx-unprivileged:1.29-alpine
ARG GIT_SHA=local
LABEL org.opencontainers.image.source="https://github.com/BinaryBhakti/devops-homework" \
      org.opencontainers.image.title="incidentdesk-frontend" \
      org.opencontainers.image.revision="${GIT_SHA}"
# The base image lags behind Alpine security fixes: Trivy found 42 fixable HIGH CVEs (curl,
# OpenSSL, c-ares) in it and the security gate blocked the build. Upgrade the OS packages, and
# remove curl altogether — nginx doesn't need it (the healthcheck uses busybox wget).
USER root
RUN apk upgrade --no-cache && apk del --no-cache curl
ENV BACKEND_URL=http://backend:8000 \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
COPY templates/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
# the base image already runs as nginx (101); stated explicitly so it can't silently change
USER 101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
