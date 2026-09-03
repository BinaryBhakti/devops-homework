# ---- Nginx Hello World ---------------------------------------------------
FROM nginx:1.27-alpine

# Replace the default site config
COPY default.conf /etc/nginx/conf.d/default.conf

# Copy the static site
COPY public/ /usr/share/nginx/html/

EXPOSE 80

# The base image already runs: nginx -g 'daemon off;'
