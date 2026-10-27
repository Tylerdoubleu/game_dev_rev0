#!/usr/bin/env node
/**
 * Edgegap Arbitrium Zero-Lag Container Bootstrapper (`deploy/edgegap_bootstrap.js`)
 * 1. Immediately binds HTTP + WebSocket port 8080 (`ARBITRIUM_PORT_GAMEPORT_INTERNAL` / `PORT`)
 *    so Edgegap's Arbitrium TCP/WS readiness probe succeeds immediately.
 * 2. Downloads Godot 4.7.2 headless and clones `Tylerdoubleu/game_dev_rev0` in the background.
 * 3. Starts the authoritative Godot 4.7.2 headless server on `WS_PORT=9080` and pipes incoming
 *    WebSocket connections (`Upgrade: websocket`) directly to Godot.
 */

const http = require("http");
const net = require("net");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const HTTP_PORT = parseInt(
  process.env.ARBITRIUM_PORT_GAMEPORT_INTERNAL ||
    process.env.ARBITRIUM_PORT_HTTP_INTERNAL ||
    process.env.PORT ||
    "8080",
  10
);
const GODOT_WS_PORT = parseInt(
  process.env.ARBITRIUM_PORT_WS_INTERNAL || process.env.WS_PORT || "9080",
  10
);
const APP_DIR = "/tmp/paintball_app";
const WEB_ROOT = path.join(APP_DIR, "build", "web");

let setupStatus = "bootstrapping";
let currentGodotProc = null;
const setupLog = [];
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  setupLog.push(line);
  if (setupLog.length > 120) setupLog.shift();
}

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".json": "application/json; charset=utf-8",
};

const server = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  let pathname = decodeURIComponent(parsedUrl.pathname);

  if (pathname === "/pull" || pathname === "/reload") {
    const upd = spawn("/bin/sh", ["-c", `cd ${APP_DIR} && git fetch origin main && git reset --hard origin/main`]);
    upd.on("exit", (c) => {
      log(`Pulled latest origin/main (exit=${c}), restarting Godot server...`);
      if (currentGodotProc) {
        try { currentGodotProc.kill("SIGTERM"); } catch (_) {}
      }
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ status: "reloaded", exit_code: c }));
    });
    return;
  }

  if (pathname === "/healthz" || pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        status: "ok",
        setup_status: setupStatus,
        service: "2000s-pro-paintball-server",
        version: "0.2.2-multiplayer",
        http_port: HTTP_PORT,
        godot_ws_port: GODOT_WS_PORT,
        arbitrium_public_ip: process.env.ARBITRIUM_PUBLIC_IP || null,
        logs: setupLog.slice(-20),
      })
    );
    return;
  }

  if (pathname === "/" || pathname === "") pathname = "/index.html";
  const safePath = path.normalize(pathname).replace(/^(\.\.(\/|\\|$))+/, "");
  const filePath = path.join(WEB_ROOT, safePath);

  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(`<!doctype html><html><body style="background:#0d0f12;color:#e8ecf2;font-family:monospace;padding:24px;">
      <h2 style="color:#f5d423;">2000s Pro Paintball — Edgegap Arbitrium Server (${setupStatus})</h2>
      <p>WebSocket Endpoint: <code>wss://${req.headers.host || "localhost"}/ws</code></p>
      <p><a style="color:#35ff88" href="https://tylerdoubleu.github.io/game_dev_rev0/?server=wss://${req.headers.host || "localhost"}/ws">
        &gt;&gt; Click Here to Launch WebGL2 Client Connected to This Edgegap Server &lt;&lt;
      </a></p>
      <pre style="background:#161920;padding:12px;border:1px solid #333;">${setupLog.join("\n")}</pre>
    </body></html>`);
    return;
  }

  const stats = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  res.writeHead(200, {
    "Content-Type": MIME_TYPES[ext] || "application/octet-stream",
    "Content-Length": stats.size,
    "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=3600",
  });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  fs.createReadStream(filePath).pipe(res);
});

server.on("upgrade", (req, clientSocket, head) => {
  clientSocket.setNoDelay(true);
  const connectWithRetry = (attemptsLeft) => {
    const upstream = net.connect(GODOT_WS_PORT, "127.0.0.1", () => {
      upstream.setNoDelay(true);
      let rawHeaders = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        rawHeaders += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
      }
      rawHeaders += "\r\n";
      upstream.write(rawHeaders);
      if (head && head.length > 0) upstream.write(head);
      clientSocket.pipe(upstream);
      upstream.pipe(clientSocket);
    });
    upstream.on("error", () => {
      if (attemptsLeft > 0) {
        setTimeout(() => connectWithRetry(attemptsLeft - 1), 1000);
      } else {
        try {
          clientSocket.write("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n");
        } catch (_) {}
        clientSocket.destroy();
      }
    });
    clientSocket.on("error", () => upstream.destroy());
  };
  connectWithRetry(20);
});

server.listen(HTTP_PORT, "0.0.0.0", () => {
  log(`HTTP + WS Gateway listening on 0.0.0.0:${HTTP_PORT} -> Godot WS 127.0.0.1:${GODOT_WS_PORT}`);
  bootstrapGodot();
});

function startGodotLoop() {
  setupStatus = "ready";
  log("Spawning headless Godot 4.7.2 dedicated server...");
  const p = currentGodotProc = spawn(
    "/tmp/Godot_v4.7.2-stable_linux.x86_64",
    ["--headless", "--low-processor-mode", "--path", APP_DIR, "--", "--server", `--port=${GODOT_WS_PORT}`],
    {
      env: {
        ...process.env,
        DEDICATED_SERVER: "1",
        WS_PORT: String(GODOT_WS_PORT),
        HOME: "/tmp",
      },
    }
  );
  p.stdout.on("data", (d) => log("[Godot] " + d.toString().trim()));
  p.stderr.on("data", (d) => log("[Godot-Err] " + d.toString().trim()));
  p.on("exit", (code) => {
    log(`Godot exited with code ${code}, restarting in 2s...`);
    setTimeout(startGodotLoop, 2000);
  });
}

function bootstrapGodot() {
  const script = `
    set -e
    if [ ! -f /tmp/Godot_v4.7.2-stable_linux.x86_64 ]; then
      curl -fsSL https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o /tmp/godot.zip
      python3 -c "import zipfile; zipfile.ZipFile('/tmp/godot.zip').extractall('/tmp')" 2>/dev/null || unzip -q -o /tmp/godot.zip -d /tmp/
      chmod +x /tmp/Godot_v4.7.2-stable_linux.x86_64
      rm -f /tmp/godot.zip
    fi
    if [ ! -d ${APP_DIR} ]; then
      git clone --depth 1 https://github.com/Tylerdoubleu/game_dev_rev0.git ${APP_DIR}
    fi
    HOME=/tmp /tmp/Godot_v4.7.2-stable_linux.x86_64 --headless --path ${APP_DIR} --import >/dev/null 2>&1 || true
  `;
  log("Downloading Godot 4.7.2 & repo in background...");
  const sh = spawn("/bin/sh", ["-c", script]);
  sh.stdout.on("data", (d) => log("[Setup] " + d.toString().trim()));
  sh.stderr.on("data", (d) => log("[Setup] " + d.toString().trim()));
  sh.on("exit", (code) => {
    log(`Bootstrap shell finished with code ${code}`);
    startGodotLoop();
  });
}
