# ===== Build Stage =====
FROM node:22-alpine AS build

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .
RUN npm run build

# ===== Runtime Stage =====
FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="MachineGuru Frontend"
LABEL org.opencontainers.image.description="React UI for MachineGuru RAG system"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache curl

COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=build /build/dist /usr/share/nginx/html

RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

USER nginx

CMD ["nginx", "-g", "daemon off;"]
