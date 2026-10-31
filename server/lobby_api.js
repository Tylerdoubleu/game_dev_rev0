"use strict";
/**
 * v0.5 PB-12 lobby browser API helpers (pure functions, unit-tested by server/test/lobby_api.test.js).
 *
 * The headless Godot room router (scripts/autoload/network_lobby.gd) writes its real room state to
 * LOBBY_STATE_FILE as {"version":1,"generated_at":<unix s>,"max_per_team":5,"lobbies":[{id,name,map,mode,
 * players:{red,blue},max_per_team,status,bots}]}. This module turns that into the public /api/lobbies shape:
 *
 *   {"lobbies":[{"id":"lobby_01","name":"Lobby 01","map":"speedball","mode":"deathmatch",
 *                "players":{"red":3,"blue":4},"max_per_team":5,"status":"waiting","bots":false,
 *                "join_url":"https://tylerdoubleu.github.io/game_dev_rev0/?server=wss://host:port/ws&room=lobby_01&map=speedball"}]}
 */

const DEFAULT_GAME_CLIENT_URL = "https://tylerdoubleu.github.io/game_dev_rev0/";
const DEFAULT_CORS_ORIGINS = [
  "https://tylerdoubleu.github.io",
  "https://play.jeetball.com",
  "https://test.jeetball.com",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
];
const STATE_STALE_MS = 10000;
const MAPS = new Set(["speedball", "woodsball_crash"]);
const MODES = new Set(["deathmatch", "ctf", "bots_test"]);
const STATUSES = new Set(["waiting", "in_match", "full"]);

function corsOrigins(env = process.env) {
  const raw = (env.CORS_ORIGINS || "").trim();
  if (!raw) return DEFAULT_CORS_ORIGINS;
  return raw.split(",").map((s) => s.trim().replace(/\/+$/, "")).filter(Boolean);
}

/** Headers for an /api/* response: echo the Origin only if it is allow-listed. */
function apiCorsHeaders(origin, env = process.env) {
  const h = { Vary: "Origin" };
  const list = corsOrigins(env);
  if (origin && (list.includes(origin) || list.includes("*"))) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Methods"] = "GET, POST, PUT, OPTIONS";
    h["Access-Control-Allow-Headers"] = "Authorization, Content-Type";
    h["Access-Control-Max-Age"] = "600";
  }
  return h;
}

/** Public WS URL players should connect to: PUBLIC_WS_URL, else derived from the request Host. */
function publicWsUrl(headers = {}, env = process.env) {
  if (env.PUBLIC_WS_URL) return env.PUBLIC_WS_URL.trim();
  const host = String(headers["x-forwarded-host"] || headers.host || "127.0.0.1:8080").split(",")[0].trim();
  const fwdProto = String(headers["x-forwarded-proto"] || "").split(",")[0].trim();
  const local = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host);
  const secure = fwdProto ? fwdProto === "https" : !local;
  return `${secure ? "wss" : "ws"}://${host}/ws`;
}

function buildJoinUrl(lobby, wsUrl, env = process.env) {
  let base = (env.GAME_CLIENT_URL || DEFAULT_GAME_CLIENT_URL).trim();
  if (!base.includes("?") && !base.endsWith("/") && !/\.html?$/.test(base)) base += "/";
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}server=${wsUrl}&room=${encodeURIComponent(lobby.id)}&map=${encodeURIComponent(lobby.map)}`;
}

function normalizeLobby(raw, maxPerTeam) {
  if (!raw || typeof raw !== "object" || typeof raw.id !== "string") return null;
  const players = raw.players && typeof raw.players === "object" ? raw.players : {};
  const red = Math.max(0, parseInt(players.red, 10) || 0);
  const blue = Math.max(0, parseInt(players.blue, 10) || 0);
  const max = parseInt(raw.max_per_team, 10) || maxPerTeam || 5;
  const mode = MODES.has(raw.mode) ? raw.mode : "deathmatch";
  let status = STATUSES.has(raw.status) ? raw.status : "waiting";
  if (red + blue >= max * 2) status = "full";
  return {
    id: raw.id,
    name: typeof raw.name === "string" ? raw.name : raw.id,
    map: MAPS.has(raw.map) ? raw.map : "speedball",
    mode,
    players: { red, blue },
    max_per_team: max,
    status,
    bots: mode === "bots_test" || raw.bots === true,
  };
}

/**
 * @returns {{status:number, body:object}}
 */
function buildLobbiesResponse(stateDoc, { headers = {}, env = process.env, now = Date.now(), staleMs = STATE_STALE_MS } = {}) {
  if (!stateDoc || !Array.isArray(stateDoc.lobbies)) {
    return { status: 503, body: { lobbies: [], error: "game server room state unavailable" } };
  }
  const ageMs = now - Number(stateDoc.generated_at || 0) * 1000;
  if (!(ageMs <= staleMs)) {
    return { status: 503, body: { lobbies: [], error: "game server room state is stale" } };
  }
  const wsUrl = publicWsUrl(headers, env);
  const lobbies = stateDoc.lobbies
    .map((l) => normalizeLobby(l, stateDoc.max_per_team))
    .filter(Boolean)
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((l) => ({ ...l, join_url: buildJoinUrl(l, wsUrl, env) }));
  return { status: 200, body: { lobbies } };
}

const total = (l) => l.players.red + l.players.blue;

/** Quick-join: the "waiting" lobby with the most players that still has room (ties -> lowest id). */
function pickQuickJoin(lobbies) {
  let best = null;
  for (const l of lobbies) {
    if (l.status !== "waiting" || total(l) >= l.max_per_team * 2) continue;
    if (!best || total(l) > total(best) || (total(l) === total(best) && l.id < best.id)) best = l;
  }
  return best;
}

module.exports = {
  DEFAULT_GAME_CLIENT_URL,
  DEFAULT_CORS_ORIGINS,
  STATE_STALE_MS,
  corsOrigins,
  apiCorsHeaders,
  publicWsUrl,
  buildJoinUrl,
  normalizeLobby,
  buildLobbiesResponse,
  pickQuickJoin,
};
