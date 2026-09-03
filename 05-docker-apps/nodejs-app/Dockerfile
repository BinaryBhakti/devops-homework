# ---- Node.js Hello World -------------------------------------------------
FROM node:20-alpine

# Everything below happens inside /app in the image
WORKDIR /app

# Copy manifests FIRST so this layer is cached when only source code changes
COPY package*.json ./
RUN npm install --omit=dev

# Now copy the application source
COPY server.js ./

# Document the port the app listens on
EXPOSE 3000

# Run as the unprivileged user that the node image already provides
USER node

CMD ["node", "server.js"]
