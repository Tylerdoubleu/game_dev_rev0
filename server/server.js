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
const lobbyApi = require("./lobby_api");
const profiles = require("./profile_store");

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

// v0.5: the headless Godot room router writes its real room state here; /api/lobbies serves it.
const LOBBY_STATE_FILE = path.resolve(
  process.env.LOBBY_STATE_FILE || path.join(require("os").tmpdir(), `paintball_lobbies_${GODOT_WS_PORT}.json`)
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

// v0.7 profiles + clout: JSON store under DATA_DIR (outside the checkout). INTERNAL_KEY guards
// POST /internal/match_result; if unset, a random one is generated and handed to the spawned Godot server.
const DATA_DIR = profiles.defaultDataDir();
const INTERNAL_KEY = (process.env.INTERNAL_KEY || "").trim() || require("crypto").randomBytes(24).toString("hex");
const profileStore = new profiles.ProfileStore({ dataDir: DATA_DIR });
const profileLimiter = new profiles.RateLimiter(
  parseInt(process.env.PROFILE_CREATE_LIMIT_PER_HOUR || "", 10) || profiles.CREATE_LIMIT_PER_HOUR
);
function flushProfilesAndExit() {
  try {
    profileStore.flush();
  } catch (e) {
    console.error("[Profiles] flush failed:", e.message);
  }
  process.exit(0);
}
process.on("SIGTERM", flushProfilesAndExit);
process.on("SIGINT", flushProfilesAndExit);

let godotProc = null;
function startGodotServerIfRequested() {
  if (process.env.AUTO_START_GODOT !== "1") return;
  const linuxBin = path.resolve(__dirname, "..", "build", "linux", "paintball_server.x86_64");
  const cmd = fs.existsSync(linuxBin) ? linuxBin : "godot";
  // v0.5: no --low-processor-mode (it sleeps between frames and throttles the room tick / 20 Hz snapshots);
  // --max-fps caps the headless loop so it does not spin a whole core. GODOT_MAX_FPS overrides (default 60).
  const maxFps = String(parseInt(process.env.GODOT_MAX_FPS || "60", 10) || 60);
  const args = fs.existsSync(linuxBin)
    ? ["--headless", "--max-fps", maxFps, "--", "--server", `--port=${GODOT_WS_PORT}`]
    : ["--headless", "--max-fps", maxFps, "--path", path.resolve(__dirname, ".."), "--", "--server", `--port=${GODOT_WS_PORT}`];

  console.log(`[Supervisor] Starting headless Godot server: ${cmd} ${args.join(" ")}`);
  godotProc = spawn(cmd, args, {
    stdio: "inherit",
    env: {
      ...process.env,
      DEDICATED_SERVER: "1",
      WS_PORT: String(GODOT_WS_PORT),
      LOBBY_STATE_FILE,
      INTERNAL_KEY,
      PROFILE_API_URL: `http://127.0.0.1:${HTTP_PORT}`,
    },
  });
  godotProc.on("exit", (code, sig) => {
    console.warn(`[Supervisor] Headless Godot exited (code=${code}, sig=${sig}). Restarting in 2s...`);
    setTimeout(startGodotServerIfRequested, 2000);
  });
}

startGodotServerIfRequested();

function readLobbyState(cb) {
  fs.readFile(LOBBY_STATE_FILE, "utf8", (err, text) => {
    if (err) return cb(null);
    try {
      cb(JSON.parse(text));
    } catch (_) {
      cb(null);
    }
  });
}

function sendJson(res, status, body, extraHeaders = {}) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...extraHeaders,
  });
  res.end(JSON.stringify(body));
}

function handleApi(req, res, parsedUrl) {
  const cors = lobbyApi.apiCorsHeaders(req.headers.origin);
  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    res.end();
    return;
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    sendJson(res, 405, { error: "method not allowed" }, { ...cors, Allow: "GET, OPTIONS" });
    return;
  }
  readLobbyState((doc) => {
    const out = lobbyApi.buildLobbiesResponse(doc, { headers: req.headers });
    if (parsedUrl.pathname === "/api/lobbies") {
      sendJson(res, out.status, out.body, cors);
      return;
    }
    // /api/quickjoin
    if (out.status !== 200) {
      sendJson(res, out.status, { lobby: null, join_url: null, error: out.body.error }, cors);
      return;
    }
    const pick = lobbyApi.pickQuickJoin(out.body.lobbies);
    if (!pick) {
      sendJson(res, 404, { lobby: null, join_url: null, error: "no waiting lobby with room" }, cors);
      return;
    }
    if (parsedUrl.searchParams.get("redirect") === "1") {
      res.writeHead(302, { ...cors, Location: pick.join_url, "Cache-Control": "no-store" });
      res.end();
      return;
    }
    sendJson(res, 200, { lobby: pick, join_url: pick.join_url }, cors);
  });
}

const server = http.createServer((req, res) => {
  const earlyUrl = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (earlyUrl.pathname === "/api/lobbies" || earlyUrl.pathname === "/api/quickjoin") {
    handleApi(req, res, earlyUrl);
    return;
  }
  if (
    profiles.handleProfileRequest(req, res, earlyUrl, {
      store: profileStore,
      internalKey: INTERNAL_KEY,
      limiter: profileLimiter,
      cors: lobbyApi.apiCorsHeaders(req.headers.origin),
      sendJson,
    })
  ) {
    return;
  }
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
        version: "0.5.0-rooms",
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
  console.log(`[Server] v0.7 profiles stored in ${DATA_DIR}${process.env.INTERNAL_KEY ? "" : " (INTERNAL_KEY generated for this run)"}`);
});
