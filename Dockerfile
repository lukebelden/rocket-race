# Rocket Race: one container that serves the web build and runs the multiplayer server.
# Used by DigitalOcean App Platform (see .do/app.yaml). Re-export the game into build/web
# from Godot before pushing; this image just copies it.
FROM node:22-alpine
WORKDIR /app

COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev

COPY server/ ./server/
COPY build/web/ ./build/web/

ENV NODE_ENV=production PORT=8080
EXPOSE 8080
CMD ["node", "server/index.js"]
