# ---- Apache HTTP Server Hello World --------------------------------------
FROM httpd:2.4-alpine

# httpd serves everything in this directory by default
COPY public/ /usr/local/apache2/htdocs/

EXPOSE 80

# The base image already runs: httpd-foreground
