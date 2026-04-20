FROM node:22-slim AS builder

WORKDIR /app

# ── Build server ──────────────────────────────────────────────────────────────
COPY server/package.json server/package-lock.json* ./server/
RUN cd server && npm install

COPY server ./server
RUN cd server && npm run build

# ── Build client ──────────────────────────────────────────────────────────────
COPY client/package.json client/package-lock.json* ./client/
RUN cd client && npm install

COPY client ./client
RUN cd client && npm run build

# ── Production image ──────────────────────────────────────────────────────────
FROM node:22-alpine AS runner

WORKDIR /app

# esbuild bundles almost everything — but pdfkit is external because it
# loads font files at runtime via fs, so node_modules must be present
COPY --from=builder /app/server/node_modules ./node_modules

# The compiled server bundle
COPY --from=builder /app/server/dist ./dist

# The built SPA — Express serves it as static files in production
COPY --from=builder /app/client/dist/public ./public

EXPOSE 3000

ENV PORT=3000
ENV NODE_ENV=production

CMD ["node", "--enable-source-maps", "./dist/index.mjs"]
