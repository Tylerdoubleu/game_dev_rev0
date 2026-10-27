FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# Install Godot 4.7.2 headless runtime + export templates (for authoritative dedicated server & WebGL2 client export)
RUN curl -fsSL https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /usr/local/bin/ \
    && mv /usr/local/bin/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -f /tmp/godot.zip \
    && mkdir -p /root/.local/share/godot/export_templates/4.7.2.stable \
    && curl -fsSL https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz -o /tmp/templates.tpz \
    && unzip -q /tmp/templates.tpz -d /tmp/templates \
    && mv /tmp/templates/templates/* /root/.local/share/godot/export_templates/4.7.2.stable/ \
    && rm -rf /tmp/templates.tpz /tmp/templates

WORKDIR /app
COPY . /app

# Import project assets and build WebGL2 bundle if not pre-exported
RUN godot --headless --path /app --import || true
RUN if [ ! -f /app/build/web/index.html ]; then \
      mkdir -p /app/build/web && \
      godot --headless --path /app --export-release "Web" /app/build/web/index.html; \
    fi

ENV PORT=8080
ENV WS_PORT=9080
ENV AUTO_START_GODOT=1
ENV DEDICATED_SERVER=1

EXPOSE 8080 9080

CMD ["node", "/app/server/server.js"]
