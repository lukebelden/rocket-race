# Rocket Race: one container that serves the web build, runs multiplayer rooms and stores
# player accounts (SQLite in /data). Re-export the game into build/web from Godot before
# building; this image just copies it. See docker-compose.yml for running it on a Droplet.
FROM node:24-alpine
WORKDIR /app

COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev

COPY catalog.json ./
COPY server/ ./server/
COPY build/web/ ./build/web/

ENV NODE_ENV=production PORT=8080 DATA_DIR=/data
VOLUME /data
EXPOSE 8080
CMD ["node", "server/index.js"]
