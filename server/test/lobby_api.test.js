"use strict";
// v0.5 PB-12: GET /api/lobbies + /api/quickjoin shape, CORS and staleness.
// Run: node --test server/test/   (optionally GODOT_LOBBY_STATE=/path/to/real/godot/state.json)
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");
const { spawn } = require("child_process");
const api = require("../lobby_api");

const ENV = { GAME_CLIENT_URL: "https://tylerdoubleu.github.io/game_dev_rev0/" };
const HEADERS = { host: "abc123.pr.edgegap.net:31351" };

function fixture(now = Date.now()) {
  const lobbies = [];
  for (let i = 1; i <= 10; i++) {
    lobbies.push({
      id: `lobby_${String(i).padStart(2, "0")}`,
      name: `Lobby ${String(i).padStart(2, "0")}`,
      map: i % 2 ? "speedball" : "woodsball_crash",
      mode: "deathmatch",
      players: { red: 0, blue: 0 },
      max_per_team: 5,
      status: "waiting",
      bots: false,
    });
  }
  lobbies[0].players = { red: 3, blue: 4 };
  lobbies[1] = { ...lobbies[1], players: { red: 5, blue: 5 }, status: "full", mode: "ctf" };
  lobbies[2] = { ...lobbies[2], players: { red: 4, blue: 4 }, status: "in_match" };
  lobbies[3] = { ...lobbies[3], players: { red: 4, blue: 3 }, mode: "bots_test", bots: true };
  return { version: 1, generated_at: now / 1000, max_per_team: 5, lobbies };
}

function assertLobbyShape(l) {
  assert.deepEqual(Object.keys(l).sort(), ["bots", "id", "join_url", "map", "max_per_team", "mode", "name", "players", "status"]);
  assert.match(l.id, /^lobby_(0[1-9]|10)$/);
  assert.equal(l.name, `Lobby ${l.id.slice(6)}`);
  assert.ok(["speedball", "woodsball_crash"].includes(l.map));
  assert.ok(["deathmatch", "ctf", "bots_test"].includes(l.mode));
  assert.deepEqual(Object.keys(l.players).sort(), ["blue", "red"]);
  assert.ok(Number.isInteger(l.players.red) && Number.isInteger(l.players.blue));
  assert.equal(l.max_per_team, 5);
  assert.ok(["waiting", "in_match", "full"].includes(l.status));
  assert.equal(typeof l.bots, "boolean");
  assert.ok(l.join_url.startsWith("https://tylerdoubleu.github.io/game_dev_rev0/?server="));
  const u = new URL(l.join_url);
  assert.equal(u.searchParams.get("room"), l.id);
  assert.equal(u.searchParams.get("map"), l.map);
  assert.match(u.searchParams.get("server"), /^wss?:\/\/.+\/ws$/);
}

test("buildLobbiesResponse returns the exact public shape", () => {
  const out = api.buildLobbiesResponse(fixture(), { headers: HEADERS, env: ENV });
  assert.equal(out.status, 200);
  assert.deepEqual(Object.keys(out.body), ["lobbies"]);
  assert.equal(out.body.lobbies.length, 10);
  out.body.lobbies.forEach(assertLobbyShape);
  const l1 = out.body.lobbies[0];
  assert.deepEqual(l1, {
    id: "lobby_01",
    name: "Lobby 01",
    map: "speedball",
    mode: "deathmatch",
    players: { red: 3, blue: 4 },
    max_per_team: 5,
    status: "waiting",
    bots: false,
    join_url: "https://tylerdoubleu.github.io/game_dev_rev0/?server=wss://abc123.pr.edgegap.net:31351/ws&room=lobby_01&map=speedball",
  });
  assert.equal(out.body.lobbies[3].bots, true);
});

test("PUBLIC_WS_URL overrides the derived server, localhost derives ws://", () => {
  const a = api.buildLobbiesResponse(fixture(), { headers: HEADERS, env: { ...ENV, PUBLIC_WS_URL: "wss://pb.example.com/ws" } });
  assert.ok(a.body.lobbies[0].join_url.includes("?server=wss://pb.example.com/ws&room=lobby_01"));
  assert.equal(api.publicWsUrl({ host: "127.0.0.1:8080" }, {}), "ws://127.0.0.1:8080/ws");
  assert.equal(api.publicWsUrl({ host: "x.y:1", "x-forwarded-proto": "http" }, {}), "ws://x.y:1/ws");
});

test("full lobbies are reported full even if Godot said waiting", () => {
  const doc = fixture();
  doc.lobbies[5] = { ...doc.lobbies[5], players: { red: 5, blue: 5 }, status: "waiting" };
  const out = api.buildLobbiesResponse(doc, { headers: HEADERS, env: ENV });
  assert.equal(out.body.lobbies[5].status, "full");
});

test("missing or stale Godot state -> 503 with empty list", () => {
  assert.equal(api.buildLobbiesResponse(null).status, 503);
  const stale = api.buildLobbiesResponse(fixture(Date.now() - 60000), { headers: HEADERS, env: ENV });
  assert.equal(stale.status, 503);
  assert.deepEqual(stale.body.lobbies, []);
});

test("quick-join picks the waiting lobby with the most players that still has room", () => {
  const { lobbies } = api.buildLobbiesResponse(fixture(), { headers: HEADERS, env: ENV }).body;
  assert.equal(api.pickQuickJoin(lobbies).id, "lobby_01"); // 7 players; lobby_02 full, lobby_03 in_match
  const tie = lobbies.map((l) => ({ ...l, players: { red: 0, blue: 0 }, status: "waiting" }));
  assert.equal(api.pickQuickJoin(tie).id, "lobby_01");
  assert.equal(api.pickQuickJoin(lobbies.filter((l) => l.status !== "waiting")), null);
});

test("CORS: github.io allow-listed, random origins are not", () => {
  const ok = api.apiCorsHeaders("https://tylerdoubleu.github.io", {});
  assert.equal(ok["Access-Control-Allow-Origin"], "https://tylerdoubleu.github.io");
  assert.equal(ok.Vary, "Origin");
  assert.equal(api.apiCorsHeaders("https://evil.example", {})["Access-Control-Allow-Origin"], undefined);
});

test("real Godot room-state document (if provided) maps to the public shape", { skip: !process.env.GODOT_LOBBY_STATE }, () => {
  const doc = JSON.parse(fs.readFileSync(process.env.GODOT_LOBBY_STATE, "utf8"));
  doc.generated_at = Date.now() / 1000;
  const out = api.buildLobbiesResponse(doc, { headers: HEADERS, env: ENV });
  assert.equal(out.status, 200);
  assert.equal(out.body.lobbies.length, 10);
  out.body.lobbies.forEach(assertLobbyShape);
});

function get(port, p, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: "127.0.0.1", port, path: p, headers }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body }));
    });
    req.on("error", reject);
  });
}

test("server.js serves /api/lobbies and /api/quickjoin over HTTP", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pb-api-"));
  const stateFile = path.join(dir, "state.json");
  fs.writeFileSync(stateFile, JSON.stringify(fixture()));
  const port = 18000 + Math.floor(Math.random() * 2000);
  const proc = spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
    env: { ...process.env, PORT: String(port), LOBBY_STATE_FILE: stateFile, AUTO_START_GODOT: "0", ...ENV },
    stdio: "ignore",
  });
  t.after(() => proc.kill());
  let r;
  for (let i = 0; i < 50; i++) {
    try {
      r = await get(port, "/api/lobbies", { Origin: "https://tylerdoubleu.github.io", Host: "abc123.pr.edgegap.net:31351" });
      break;
    } catch (_) {
      await new Promise((ok) => setTimeout(ok, 100));
    }
  }
  assert.ok(r, "server.js started");
  assert.equal(r.status, 200);
  assert.equal(r.headers["access-control-allow-origin"], "https://tylerdoubleu.github.io");
  const body = JSON.parse(r.body);
  assert.equal(body.lobbies.length, 10);
  body.lobbies.forEach(assertLobbyShape);
  const q = await get(port, "/api/quickjoin", { Host: "abc123.pr.edgegap.net:31351" });
  assert.equal(q.status, 200);
  assert.equal(JSON.parse(q.body).lobby.id, "lobby_01");
  const red = await get(port, "/api/quickjoin?redirect=1", { Host: "abc123.pr.edgegap.net:31351" });
  assert.equal(red.status, 302);
  assert.ok(red.headers.location.includes("room=lobby_01"));
  fs.writeFileSync(stateFile, JSON.stringify(fixture(Date.now() - 60000)));
  const stale = await get(port, "/api/lobbies");
  assert.equal(stale.status, 503);
});
