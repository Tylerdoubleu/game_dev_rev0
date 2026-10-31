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

  // CORS preflight: server.js owns it for every /api/* path
  for (const p of ["/api/profile", "/api/profile/callsign", "/api/profile/career", "/api/profile/public/x", "/api/lobbies", "/api/quickjoin", "/api/other"]) {
    const pre = await fetch(base + p, { method: "OPTIONS", headers: { Origin: ORIGIN, "Access-Control-Request-Method": "PUT", "Access-Control-Request-Headers": "authorization,content-type" } });
    assert.equal(pre.status, 204, p);
    assert.equal(pre.headers.get("access-control-allow-origin"), ORIGIN, p);
    assert.equal(pre.headers.get("access-control-allow-methods"), "GET, POST, PUT, OPTIONS", p);
    assert.equal(pre.headers.get("access-control-allow-headers"), "Authorization, Content-Type", p);
    assert.equal(pre.headers.get("access-control-max-age"), "600", p);
    assert.match(pre.headers.get("vary") || "", /Origin/, p);
  }
  const evil = await fetch(`${base}/api/profile`, { method: "OPTIONS", headers: { Origin: "https://evil.example" } });
  assert.equal(evil.status, 204);
  assert.equal(evil.headers.get("access-control-allow-origin"), null, "unlisted origin not echoed");

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
  assert.deepEqual(Object.keys(g.json).sort(), ["callsign", "career", "clout", "clout_by_source", "created_at", "profile_id", "stats"]);
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
  assert.deepEqual(Object.keys(pub.json).sort(), ["callsign", "clout", "clout_by_source", "stats"]);
  assert.deepEqual(pub.json.clout_by_source, { online: wantB, solo: 0 });
  assert.equal(pub.json.clout, wantB);
  assert.equal(pub.json.stats.eliminations, 50);
  assert.equal((await call(base, "GET", "/api/profile/public/nobody_here")).status, 404);

  // rate limit (4/hour in this test; 2 used above)
  assert.equal((await call(base, "POST", "/api/profile")).status, 201);
  assert.equal((await call(base, "POST", "/api/profile")).status, 201);
  assert.equal((await call(base, "POST", "/api/profile")).status, 429);

  // solo awards (client-reported): star +100 once, challenge +50 then +13, tier +500 once
  const solo = (body, token = a.json.token) => call(base, "POST", "/api/profile/solo_award", { token, body });
  let r = await solo({ kind: "star", id: "speedball:s1" });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { awarded: 100, clout: wantA + 100, clout_by_source: { online: wantA, solo: 100 } });
  assert.equal((await solo({ kind: "star", id: "speedball:s1" })).json.awarded, 0, "same star again: 0");
  assert.equal((await solo({ kind: "star", id: "speedball:s2" })).json.awarded, 100);
  assert.equal((await solo({ kind: "challenge", id: "ch_01" })).json.awarded, 50);
  assert.equal((await solo({ kind: "challenge", id: "ch_01" })).json.awarded, 13);
  assert.equal((await solo({ kind: "challenge", id: "ch_01" })).json.awarded, 13);
  assert.equal((await solo({ kind: "tier", id: "tier.1" })).json.awarded, 500);
  r = await solo({ kind: "tier", id: "tier.1" });
  assert.equal(r.json.awarded, 0);
  const soloTotal = 100 + 100 + 50 + 13 + 13 + 500;
  assert.deepEqual(r.json.clout_by_source, { online: wantA, solo: soloTotal });
  assert.equal(r.json.clout, wantA + soloTotal);
  for (const bad of [{ kind: "medal", id: "x" }, { id: "x" }, { kind: "star" }, { kind: "star", id: "" }, { kind: "star", id: "x".repeat(65) }, { kind: "star", id: "bad id" }, { kind: "star", id: "a/b" }, { kind: "star", id: 5 }]) {
    const e = await solo(bad);
    assert.equal(e.status, 400, JSON.stringify(bad));
    assert.match(e.json.error, /^invalid_(kind|id)$/);
  }
  assert.equal((await call(base, "POST", "/api/profile/solo_award", { body: { kind: "star", id: "x" } })).status, 401);
  assert.equal((await solo({ kind: "star", id: "x" }, "0".repeat(64))).status, 401);
  assert.equal((await call(base, "GET", "/api/profile/solo_award", { token: a.json.token })).status, 405);
  const gs = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.deepEqual(gs.json.clout_by_source, { online: wantA, solo: soloTotal });
  // online awards keep counting as online
  await internal(base, { room: "lobby_01", mode: "deathmatch", match_id: "m2", results: [{ token: a.json.token, won: false, eliminations: 1 }] });
  const gs2 = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.deepEqual(gs2.json.clout_by_source, { online: wantA + 5, solo: soloTotal });
  assert.equal(gs2.json.clout, wantA + 5 + soloTotal);
  // 60 solo awards per minute per profile (b has used 0)
  const burst = [];
  for (let i = 0; i < 61; i++) burst.push((await solo({ kind: "challenge", id: "rl" }, b.json.token)).status);
  assert.equal(burst.filter((s) => s === 200).length, 60);
  assert.equal(burst[60], 429);
  assert.equal((await solo({ kind: "star", id: "other" })).status, 200, "limit is per profile");
  const bSolo = 50 + 59 * 13;

  // Allow-Origin on error responses too; none on /internal/*
  const o = { Origin: ORIGIN };
  const e401 = await call(base, "GET", "/api/profile", { headers: o });
  assert.equal(e401.status, 401);
  assert.equal(e401.headers.get("access-control-allow-origin"), ORIGIN);
  const e409 = await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "VIPER_77" }, headers: o });
  assert.equal(e409.status, 409);
  assert.equal(e409.headers.get("access-control-allow-origin"), ORIGIN);
  const e413 = await call(base, "PUT", "/api/profile/career", { token: a.json.token, body: { career: big }, headers: o });
  assert.equal(e413.status, 413);
  assert.equal(e413.headers.get("access-control-allow-origin"), ORIGIN);
  const e404 = await call(base, "GET", "/api/profile/public/nobody_here", { headers: o });
  assert.equal(e404.headers.get("access-control-allow-origin"), ORIGIN);
  const i1 = await internal(base, result, { "X-Internal-Key": KEY, Origin: ORIGIN });
  assert.equal(i1.headers.get("access-control-allow-origin"), null, "/internal has no CORS");
  const i2 = await internal(base, result, { "X-Internal-Key": "bad", Origin: ORIGIN });
  assert.equal(i2.status, 403);
  assert.equal(i2.headers.get("access-control-allow-origin"), null);

  // persistence across restart (SIGTERM flushes)
  await stop();
  ({ base, stop } = await startServer(t, dataDir));
  const again = await call(base, "GET", "/api/profile", { token: a.json.token });
  assert.equal(again.status, 200);
  assert.equal(again.json.callsign, "Viper-2");
  assert.equal(again.json.clout, wantA + 5 + soloTotal + 100);
  assert.deepEqual(again.json.clout_by_source, { online: wantA + 5, solo: soloTotal + 100 });
  assert.equal((await solo({ kind: "tier", id: "tier.1" })).json.awarded, 0, "solo ids persisted");
  assert.equal((await solo({ kind: "challenge", id: "ch_01" })).json.awarded, 13);
  assert.deepEqual((await call(base, "GET", "/api/profile/public/viper_77")).json.clout_by_source, { online: wantB, solo: bSolo });
  assert.deepEqual(again.json.career, career);
  assert.equal((await call(base, "PUT", "/api/profile/callsign", { token: a.json.token, body: { callsign: "viper_77" } })).status, 409, "callsign index rebuilt on load");
  assert.equal((await internal(base, result)).json.duplicate, true, "match ids persisted");
});

test("default CORS allow-list", () => {
  const { apiCorsHeaders } = require("../lobby_api");
  for (const o of ["https://tylerdoubleu.github.io", "https://play.jeetball.com", "https://test.jeetball.com"]) {
    const h = apiCorsHeaders(o, {});
    assert.equal(h["Access-Control-Allow-Origin"], o);
    assert.equal(h["Access-Control-Allow-Methods"], "GET, POST, PUT, OPTIONS");
    assert.equal(h["Access-Control-Allow-Headers"], "Authorization, Content-Type");
    assert.equal(h["Access-Control-Max-Age"], "600");
    assert.equal(h.Vary, "Origin");
  }
  assert.equal(apiCorsHeaders("https://evil.example", {})["Access-Control-Allow-Origin"], undefined);
});

test("store: older profiles get clout_by_source {online: clout, solo: 0}", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pb_migrate_"));
  const token = "c".repeat(64);
  fs.writeFileSync(path.join(dir, "profiles.json"), JSON.stringify({ version: 1, profiles: { p_old: {
    id: "p_old", token_hash: ps.sha256(token), callsign: "Old", clout: 240,
    stats: { matches: 2, wins: 1, eliminations: 5, flags: 1, rounds_won: 0 }, career: null, created_at: "2026-10-30T00:00:00Z",
  } } }));
  const s = new ps.ProfileStore({ dataDir: dir, debounceMs: 0 });
  const p = s.byToken(token);
  assert.deepEqual(p.clout_by_source, { online: 240, solo: 0 });
  assert.deepEqual(ps.publicView(p).clout_by_source, { online: 240, solo: 0 });
  assert.deepEqual(s.soloAward(p, "star", "a"), { awarded: 100 });
  assert.deepEqual(p.clout_by_source, { online: 240, solo: 100 });
  assert.equal(p.clout, 340);
  assert.deepEqual(ps.SOLO_CLOUT, { star: { first: 100, repeat: 0 }, challenge: { first: 50, repeat: 13 }, tier: { first: 500, repeat: 0 } });
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
