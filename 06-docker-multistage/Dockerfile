# =============================================================================
#  MULTI-STAGE DOCKERFILE
#
#  A multi-stage build uses several FROM instructions in one Dockerfile.
#  Each FROM starts a new stage. Only the LAST stage becomes the final image;
#  everything else is thrown away. That lets us use a big toolchain to build
#  the app while shipping a small runtime image.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: BUILD
#   Installs ALL dependencies (including dev dependencies) and builds the app.
#   This stage is discarded - none of its layers reach the final image.
# -----------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Copy manifests first so npm install is cached when only source changes
COPY package*.json ./
RUN npm install

# Copy the rest of the source and run any build step
COPY . .


# -----------------------------------------------------------------------------
# Stage 2: PRODUCTION
#   Starts from a clean base and copies ONLY what is needed at runtime
#   out of the builder stage using COPY --from=builder.
# -----------------------------------------------------------------------------
FROM node:20-alpine AS production

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080

# Bring the manifests over from the build stage, then install prod deps only
COPY --from=builder /app/package*.json ./
RUN npm install --omit=dev && npm cache clean --force

# Bring over just the application code we actually need to run
COPY --from=builder /app/server.js ./

# The homework requires the app to listen on 8080
EXPOSE 8080

USER node

CMD ["npm", "start"]
