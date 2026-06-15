# syntax=docker/dockerfile:1
# Build context is the repo root: docker build -f src/web/Dockerfile .

# ───────────────────────────────── build ─────────────────────────────────
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json tsconfig.base.json ./
COPY src/shared/package.json ./src/shared/
COPY src/apiserver/package.json ./src/apiserver/
COPY src/runner/package.json ./src/runner/
COPY src/web/package.json ./src/web/
# NOTE: plain `npm ci` (no --omit=optional) — Vite/rollup need their platform-native
# optional package (e.g. @rollup/rollup-linux-*-musl), which --omit=optional would drop.
RUN npm ci

COPY src/web ./src/web
RUN npm run build -w @orbit/web

# ──────────────────────────────── runtime ────────────────────────────────
FROM nginx:alpine AS runtime
COPY src/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/src/web/dist /usr/share/nginx/html
EXPOSE 80
