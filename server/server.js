#!/usr/bin/env node
/**
 * 2000s Pro Paintball — Edgegap Arbitrium & Cloud Single-Port HTTP + WebSocket Server
 *
 * - Serves `build/web/` static HTML5/WebGL2 assets on PORT (default 8080, or ARBITRIUM_PORT_HTTP_INTERNAL / ARBITRIUM_PORT_GAMEPORT_INTERNAL)
 * - Upgrades incoming WebSocket connections (`Upgrade: websocket` on `/ws` or any path)
 *   and pipes raw TCP frames to the local headless Godot 4 WebSocketMultiplayerPeer server on WS_PORT (default 9080).
 * - Optionally spawns and supervises the headless Godot server process when `AUTO_START_GODOT=1`.
 */

const http = require("http");
const net = require("net");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const HTTP_PORT = parseInt(
  process.env.ARBITRIUM_PORT_HTTP_INTERNAL ||
    process.env.ARBITRIUM_PORT_GAMEPORT_INTERNAL ||
    process.env.PORT ||
    "8080",
  10
);
const GODOT_WS_PORT = parseInt(
  process.env.ARBITRIUM_PORT_WS_INTERNAL || process.env.WS_PORT || "9080",
  10
);
const WEB_ROOT = path.resolve(
  process.env.WEB_ROOT || path.join(__dirname, "..", "build", "web")
);

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

let godotProc = null;
function startGodotServerIfRequested() {
  if (process.env.AUTO_START_GODOT !== "1") return;
  const linuxBin = path.resolve(__dirname, "..", "build", "linux", "paintball_server.x86_64");
  const cmd = fs.existsSync(linuxBin) ? linuxBin : "godot";
  const args = fs.existsSync(linuxBin)
    ? ["--headless", "--low-processor-mode", "--", "--server", `--port=${GODOT_WS_PORT}`]
    : ["--headless", "--low-processor-mode", "--path", path.resolve(__dirname, ".."), "--", "--server", `--port=${GODOT_WS_PORT}`];

  console.log(`[Supervisor] Starting headless Godot server: ${cmd} ${args.join(" ")}`);
  godotProc = spawn(cmd, args, {
    stdio: "inherit",
    env: { ...process.env, DEDICATED_SERVER: "1", WS_PORT: String(GODOT_WS_PORT) },
  });
  godotProc.on("exit", (code, sig) => {
    console.warn(`[Supervisor] Headless Godot exited (code=${code}, sig=${sig}). Restarting in 2s...`);
    setTimeout(startGodotServerIfRequested, 2000);
  });
}

startGodotServerIfRequested();

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

  if (pathname === "/healthz" || pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        status: "ok",
        service: "2000s-pro-paintball-server",
        version: "0.2.2-multiplayer",
        http_port: HTTP_PORT,
        godot_ws_port: GODOT_WS_PORT,
        arbitrium_public_ip: process.env.ARBITRIUM_PUBLIC_IP || null,
      })
    );
    return;
  }

  if (pathname === "/" || pathname === "") {
    pathname = "/index.html";
  }

  const safePath = path.normalize(pathname).replace(/^(\.\.(\/|\\|$))+/, "");
  const filePath = path.join(WEB_ROOT, safePath);

  if (!filePath.startsWith(WEB_ROOT)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("404 Not Found");
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || "application/octet-stream";
    res.writeHead(200, {
      "Content-Type": contentType,
      "Content-Length": stats.size,
      "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=3600",
    });

    if (req.method === "HEAD") {
      res.end();
      return;
    }

    const stream = fs.createReadStream(filePath);
    stream.on("error", () => {
      if (!res.headersSent) res.writeHead(500);
      res.end();
    });
    stream.pipe(res);
  });
});

// Raw TCP Upgrade Proxy to Godot WebSocketMultiplayerPeer
server.on("upgrade", (req, clientSocket, head) => {
  clientSocket.setNoDelay(true);
  const upstream = net.connect(GODOT_WS_PORT, "127.0.0.1", () => {
    upstream.setNoDelay(true);
    let rawHeaders = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      rawHeaders += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
    }
    rawHeaders += "\r\n";
    upstream.write(rawHeaders);
    if (head && head.length > 0) {
      upstream.write(head);
    }
    clientSocket.pipe(upstream);
    upstream.pipe(clientSocket);
  });

  upstream.on("error", (err) => {
    console.error(`[WS Proxy] Upstream Godot WS (${GODOT_WS_PORT}) error:`, err.message);
    try {
      clientSocket.write("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n");
    } catch (_) {}
    clientSocket.destroy();
  });

  clientSocket.on("error", () => {
    upstream.destroy();
  });
});

server.listen(HTTP_PORT, "0.0.0.0", () => {
  console.log(
    `[Server] 2000s Pro Paintball HTTP + WS Gateway listening on 0.0.0.0:${HTTP_PORT} -> Godot WS 127.0.0.1:${GODOT_WS_PORT}`
  );
  console.log(`[Server] Serving HTML5 WebGL2 build from ${WEB_ROOT}`);
});
