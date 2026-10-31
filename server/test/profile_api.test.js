"use strict";
// v0.7 anonymous profile + clout API (server/profile_store.js via server.js). Run: cd server && node --test test
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const ps = require("../profile_store");

const KEY = "test-internal-key-0123456789";
const ORIGIN = "https://test.jeetball.com";

async function startServer(t, dataDir) {
  const port = 20000 + Math.floor(Math.random() * 20000);
  const proc = spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
    env: {
      ...process.env, PORT: String(port), AUTO_START_GODOT: "0", DATA_DIR: dataDir, INTERNAL_KEY: KEY,
      CORS_ORIGINS: ORIGIN, PROFILE_CREATE_LIMIT_PER_HOUR: "4",
      LOBBY_STATE_FILE: path.join(dataDir, "lobbies.json"),
    },
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 50; i++) {
    try { if ((await fetch(`${base}/healthz`)).ok) break; } catch (_) {}
    await new Promise((r) => setTimeout(r, 100));
  }
  const stop = () => new Promise((r) => { if (proc.exitCode !== null) return r(); proc.once("exit", r); proc.kill("SIGTERM"); });
  t.after(stop);
  return { base, stop };
}

async function call(base, method, p, { token, body, headers = {} } = {}) {
  const h = { ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  if (body !== undefined) h["Content-Type"] = "application/json";
  const r = await fetch(base + p, { method, headers: h, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body) });
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch (_) {}
  return { status: r.status, json, headers: r.headers };
}

const internal = (base, body, headers = { "X-Internal-Key": KEY }) => call(base, "POST", "/internal/match_result", { body, headers });

test("clout table is the documented one", () => {
  assert.deepEqual({ ...ps.CLOUT }, { ELIMINATION: 5, FLAG_CAPTURE: 25, CTF_ROUND_WIN: 25, MATCH_WIN: 75 });
  assert.equal(ps.clout({ won: true, eliminations: 2, flags: 1, rounds_won: 3 }), 75 + 10 + 25 + 75);
});

test("profile API over HTTP", async (t) => {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "pb_profiles_"));
  let { base, stop } = await startServer(t, dataDir);

  // CORS preflight allows POST/PUT + Authorization
  const pre = await fetch(`${base}/api/profile/callsign`, { method: "OPTIONS", headers: { Origin: ORIGIN, "Access-Control-Request-Method": "PUT" } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get("access-control-allow-origin"), ORIGIN);
  assert.match(pre.headers.get("access-control-allow-methods"), /PUT/);
  assert.match(pre.headers.get("access-control-allow-methods"), /POST/);
  assert.match(pre.headers.get("access-control-allow-headers"), /Authorization/);

  // create
  const a = await call(base, "POST", "/api/profile");
  assert.equal(a.status, 201);
  assert.deepEqual(Object.keys(a.json).sort(), ["callsign", "career", "clout", "profile_id", "token"]);
  assert.match(a.json.token, /^[0-9a-f]{64}$/);
  assert.equal(a.json.callsign, null);
  assert.equal(a.json.clout, 0);
  assert.equal(a.json.career, null);
  const b = await call(base, "POST", "/api/profile");
  assert.equal(b.status, 201);
  assert.notEqual(a.json.profile_id, b.json.profile_id);

  // get + 401
  const g = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.equal(g.status, 200);
  assert.deepEqual(Object.keys(g.json).sort(), ["callsign", "career", "clout", "created_at", "profile_id", "stats"]);
  assert.deepEqual(g.json.stats, { matches: 0, wins: 0, eliminations: 0, flags: 0, rounds_won: 0 });
  assert.equal(g.json.token, undefined);
  assert.equal((await call(base, "GET", "/api/profile")).status, 401);
  assert.equal((await call(base, "GET", "/api/profile", { token: "0".repeat(64) })).status, 401);
  assert.equal((await call(base, "PUT", "/api/profile/callsign", { body: { callsign: "Nope" } })).status, 401);

  // token is stored only as a hash
  await new Promise((r) => setTimeout(r, 400));
  const raw = fs.readFileSync(path.join(dataDir, "profiles.json"), "utf8");
  assert.ok(!raw.includes(a.json.token), "raw token not on disk");
  assert.ok(raw.includes(ps.sha256(a.json.token)), "token hash on disk");

  // callsigns
  for (const bad of ["ab", "x".repeat(17), "has space", "émile", "a/b", 42, null]) {
    const r = await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: bad } });
    assert.equal(r.status, 400, `bad ${bad}`);
    assert.equal(r.json.error, "invalid_callsign");
  }
  const s1 = await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "Viper_77" } });
  assert.equal(s1.status, 200);
  assert.equal(s1.json.callsign, "Viper_77");
  const taken = await call(base, "PUT", "/api/profile/callsign", { token: b.json.token, body: { callsign: "VIPER_77" } });
  assert.equal(taken.status, 409);
  assert.deepEqual(taken.json, { error: "callsign_taken" });
  const same = await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "viper_77" } });
  assert.equal(same.status, 200, "owner may change case of own name");
  assert.equal(same.json.callsign, "viper_77");
  // rename frees the old name
  assert.equal((await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "Viper-2" } })).status, 200);
  assert.equal((await call(base, "GET", "/api/profile/public/viper_77")).status, 404);
  const freed = await call(base, "PUT", "/api/profile/callsign", { token: b.json.token, body: { callsign: "Viper_77" } });
  assert.equal(freed.status, 200);

  // career
  const career = { tier: 2, stars: [1, 2, 3], unlocked: { pump: true } };
  const c1 = await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career } });
  assert.equal(c1.status, 200);
  assert.deepEqual(c1.json.career, career);
  const big = { blob: "x".repeat(33 * 1024) };
  assert.equal((await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career: big } })).status, 413);
  assert.equal((await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career: { blob: "x".repeat(70 * 1024) } } })).status, 413);
  assert.equal((await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career: "str" } })).status, 400);
  assert.equal((await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: "{not json" })).status, 400);

  // clout is not client-writable
  await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career, clout: 99999 } });
  assert.equal((await call(base, "PUT", "/api/profile/clout", { token: a.json.token, body: { clout: 99999 } })).status, 404);
  assert.equal((await call(base, "GET", "/api/profile", { token: a.json.token })).json.clout, 0);

  // internal endpoint: wrong key / missing key / proxied request rejected
  const result = { room: "lobby_01", mode: "ctf", match_id: "m1", results: [
    { token: a.json.token, won: true, eliminations: 4, flags: 2, rounds_won: 3 },
    { profile_id: b.json.profile_id, won: false, eliminations: 999, flags: 99, rounds_won: 99 },
    { token: "f".repeat(64), won: true, eliminations: 1 },
  ] };
  assert.equal((await internal(base, result, { "X-Internal-Key": "wrong" })).status, 403);
  assert.equal((await internal(base, result, {})).status, 403);
  assert.equal((await internal(base, result, { "X-Internal-Key": KEY, "X-Forwarded-For": "203.0.113.9" })).status, 403);
  assert.equal((await call(base, "GET", "/internal/match_result")).status, 405);
  assert.equal((await internal(base, { nope: 1 })).status, 400);
  const ok = await internal(base, result);
  assert.equal(ok.status, 200);
  assert.equal(ok.json.ignored, 1);
  const wantA = 4 * 5 + 2 * 25 + 3 * 25 + 75; // 220
  const wantB = 50 * 5 + 5 * 25 + 5 * 25; // clamped: 500
  assert.deepEqual(ok.json.awarded, [{ profile_id: a.json.profile_id, clout: wantA }, { profile_id: b.json.profile_id, clout: wantB }]);
  const dup = await internal(base, result);
  assert.equal(dup.json.duplicate, true, "same match_id is not paid twice");
  const ga = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.equal(ga.json.clout, wantA);
  assert.deepEqual(ga.json.stats, { matches: 1, wins: 1, eliminations: 4, flags: 2, rounds_won: 3 });
  const pub = await call(base, "GET", "/api/profile/public/VIPER_77");
  assert.equal(pub.status, 200);
  assert.deepEqual(Object.keys(pub.json).sort(), ["callsign", "clout", "stats"]);
  assert.equal(pub.json.clout, wantB);
  assert.equal(pub.json.stats.eliminations, 50);
  assert.equal((await call(base, "GET", "/api/profile/public/nobody_here")).status, 404);

  // rate limit (4/hour in this test; 2 used above)
  assert.equal((await call(base, "POST", "/api/profile")).status, 201);
  assert.equal((await call(base, "POST", "/api/profile")).status, 201);
  assert.equal((await call(base, "POST", "/api/profile")).status, 429);

  // persistence across restart (SIGTERM flushes)
  await stop();
  ({ base, stop } = await startServer(t, dataDir));
  const again = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.equal(again.status, 200);
  assert.equal(again.json.callsign, "Viper-2");
  assert.equal(again.json.clout, wantA);
  assert.deepEqual(again.json.career, career);
  assert.equal((await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "viper_77" } })).status, 409, "callsign index rebuilt on load");
  assert.equal((await internal(base, result)).json.duplicate, true, "match ids persisted");
});

test("store: reload, atomic file, non-loopback rejection", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pb_store_"));
  const s = new ps.ProfileStore({ dataDir: dir, debounceMs: 0 });
  const { profile, token } = s.create();
  assert.equal(s.setCallsign(profile, "Ace"), "ok");
  s.applyMatchResult({ room: "r", mode: "deathmatch", results: [{ token, won: true, eliminations: 10 }] });
  assert.ok(!fs.readdirSync(dir).some((f) => f.endsWith(".tmp")), "no tmp file left behind");
  const s2 = new ps.ProfileStore({ dataDir: dir });
  assert.equal(s2.byToken(token).clout, 10 * 5 + 75);
  assert.equal(s2.byPublicCallsign("ACE").id, profile.id);
  const fake = (remote, headers = {}) => ({ socket: { remoteAddress: remote }, headers: { "x-internal-key": "k", ...headers } });
  assert.equal(ps.isTrustedInternal(fake("10.0.0.5"), "k"), false);
  assert.equal(ps.isTrustedInternal(fake("203.0.113.4"), "k"), false);
  assert.equal(ps.isTrustedInternal(fake("127.0.0.1"), "k"), true);
  assert.equal(ps.isTrustedInternal(fake("::1"), "k"), true);
  assert.equal(ps.isTrustedInternal(fake("127.0.0.1"), ""), false);
  assert.equal(ps.clientIp(fake("127.0.0.1", { "x-forwarded-for": "1.2.3.4, 5.6.7.8" })), "5.6.7.8");
  assert.equal(ps.clientIp(fake("9.9.9.9", { "x-forwarded-for": "1.2.3.4" })), "9.9.9.9");
});
