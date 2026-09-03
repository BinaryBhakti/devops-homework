# ---- React Hello World (multi-stage: build with Node, serve with Nginx) --

# Stage 1: install dependencies and produce the static production build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build          # output lands in /app/dist

# Stage 2: tiny Nginx image that only carries the compiled assets
FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
