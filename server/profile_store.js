"use strict";
/**
 * v0.7 anonymous profiles + clout (dependency-free JSON-file store + HTTP handlers for server.js).
 *
 * Storage: DATA_DIR/profiles.json (DATA_DIR env, default os.tmpdir()/paintball_data). DATA_DIR must live OUTSIDE
 * the git checkout, because the update script resets the checkout on every pull. Writes are debounced and atomic
 * (write <file>.tmp, then rename). Only a SHA-256 hash of each bearer token is stored; the token itself is shown
 * once, in the POST /api/profile response.
 *
 * Online clout is awarded only by POST /internal/match_result, which the headless Godot server calls at match end
 * (loopback only + X-Internal-Key). Solo clout comes from POST /api/profile/solo_award with fixed per-id values
 * (client-reported, trusted for now). Totals are split in clout_by_source {online, solo}.
 * See docs/NETWORK_EVENTS.md "v0.7 profile API".
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

/** The one table of online clout values (server-awarded only). */
const CLOUT = Object.freeze({
  ELIMINATION: 5, // per confirmed elimination
  FLAG_CAPTURE: 25, // per flag hang (capture)
  CTF_ROUND_WIN: 25, // per CTF round your team won
  MATCH_WIN: 75, // your team won the match
});
/**
 * Solo clout (client-reported via POST /api/profile/solo_award; trusted for now, no anti-cheat).
 * star: +100 the first time a star id is awarded (then 0); challenge: +50 first win per id, +13 on repeats;
 * tier: +500 the first clear of a tier id (then 0).
 */
const SOLO_CLOUT = Object.freeze({
  star: { first: 100, repeat: 0 },
  challenge: { first: 50, repeat: 13 },
  tier: { first: 500, repeat: 0 },
});
const SOLO_ID_RE = /^[A-Za-z0-9_.:-]{1,64}$/;
const SOLO_LIMIT_PER_MIN = 60;
const SOLO_MAX_IDS_PER_KIND = 1000;
/** Per-player, per-match clamps (limits abuse from a buggy or tampered match report). */
const MATCH_CAPS = Object.freeze({ eliminations: 50, flags: 5, rounds_won: 5 });
const MAX_RESULTS_PER_MATCH = 10;
const CAREER_MAX_BYTES = 32 * 1024;
const MAX_BODY_BYTES = 64 * 1024;
const CALLSIGN_RE = /^[A-Za-z0-9_-]{3,16}$/;
const CREATE_LIMIT_PER_HOUR = 10;
const RECENT_MATCH_IDS = 500;

const sha256 = (s) => crypto.createHash("sha256").update(String(s)).digest("hex");
const clampInt = (v, max) => Math.max(0, Math.min(max, Math.floor(Number(v) || 0)));

function defaultDataDir(env = process.env) {
  return path.resolve(env.DATA_DIR || path.join(os.tmpdir(), "paintball_data"));
}

function clout(r) {
  return (
    r.eliminations * CLOUT.ELIMINATION +
    r.flags * CLOUT.FLAG_CAPTURE +
    r.rounds_won * CLOUT.CTF_ROUND_WIN +
    (r.won ? CLOUT.MATCH_WIN : 0)
  );
}

class ProfileStore {
  constructor({ dataDir = defaultDataDir(), debounceMs = 250 } = {}) {
    this.dataDir = path.resolve(dataDir);
    this.file = path.join(this.dataDir, "profiles.json");
    this.debounceMs = debounceMs;
    this._timer = null;
    this.load();
  }

  load() {
    this.profiles = new Map();
    this.byTokenHash = new Map();
    this.byCallsign = new Map(); // lower-case callsign -> id
    this.recentMatches = [];
    let doc = null;
    try {
      doc = JSON.parse(fs.readFileSync(this.file, "utf8"));
    } catch (_) {}
    if (doc && doc.profiles && typeof doc.profiles === "object") {
      for (const p of Object.values(doc.profiles)) {
        if (!p || typeof p.id !== "string" || typeof p.token_hash !== "string") continue;
        normalizeProfile(p);
        this.profiles.set(p.id, p);
        this.byTokenHash.set(p.token_hash, p.id);
        if (p.callsign) this.byCallsign.set(p.callsign.toLowerCase(), p.id);
      }
      if (Array.isArray(doc.recent_matches)) this.recentMatches = doc.recent_matches.slice(-RECENT_MATCH_IDS);
    }
  }

  _schedule() {
    if (this.debounceMs <= 0) return this.flush();
    if (this._timer) return;
    this._timer = setTimeout(() => this.flush(), this.debounceMs);
    if (this._timer.unref) this._timer.unref();
  }

  flush() {
    if (this._timer) clearTimeout(this._timer);
    this._timer = null;
    fs.mkdirSync(this.dataDir, { recursive: true, mode: 0o700 });
    const doc = { version: 1, saved_at: new Date().toISOString(), profiles: {}, recent_matches: this.recentMatches };
    for (const [id, p] of this.profiles) doc.profiles[id] = p;
    const tmp = `${this.file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(doc), { mode: 0o600 });
    fs.renameSync(tmp, this.file);
  }

  create() {
    const token = crypto.randomBytes(32).toString("hex");
    const id = "p_" + crypto.randomBytes(12).toString("hex");
    const now = new Date().toISOString();
    const p = {
      id, token_hash: sha256(token), callsign: null, clout: 0,
      clout_by_source: { online: 0, solo: 0 },
      stats: { matches: 0, wins: 0, eliminations: 0, flags: 0, rounds_won: 0 },
      solo_awards: { star: {}, challenge: {}, tier: {} },
      career: null, created_at: now, updated_at: now,
    };
    this.profiles.set(id, p);
    this.byTokenHash.set(p.token_hash, id);
    this._schedule();
    return { profile: p, token };
  }

  byToken(token) {
    if (typeof token !== "string" || !/^[0-9a-f]{64}$/.test(token)) return null;
    const id = this.byTokenHash.get(sha256(token));
    return id ? this.profiles.get(id) : null;
  }

  byPublicCallsign(cs) {
    if (typeof cs !== "string") return null;
    const id = this.byCallsign.get(cs.toLowerCase());
    return id ? this.profiles.get(id) : null;
  }

  /** @returns {"ok"|"invalid_callsign"|"callsign_taken"} */
  setCallsign(p, cs) {
    if (typeof cs !== "string" || !CALLSIGN_RE.test(cs)) return "invalid_callsign";
    const key = cs.toLowerCase();
    const holder = this.byCallsign.get(key);
    if (holder && holder !== p.id) return "callsign_taken";
    if (p.callsign && p.callsign.toLowerCase() !== key) this.byCallsign.delete(p.callsign.toLowerCase());
    p.callsign = cs;
    p.updated_at = new Date().toISOString();
    this.byCallsign.set(key, p.id);
    this._schedule();
    return "ok";
  }

  /** @returns {{error:string}|{awarded:number}} */
  soloAward(p, kind, id) {
    if (typeof kind !== "string" || !Object.prototype.hasOwnProperty.call(SOLO_CLOUT, kind)) return { error: "invalid_kind" };
    if (typeof id !== "string" || !SOLO_ID_RE.test(id)) return { error: "invalid_id" };
    const seen = p.solo_awards[kind];
    const count = Object.prototype.hasOwnProperty.call(seen, id) ? seen[id] : 0;
    if (!count && Object.keys(seen).length >= SOLO_MAX_IDS_PER_KIND) return { error: "too_many_ids" };
    const awarded = count ? SOLO_CLOUT[kind].repeat : SOLO_CLOUT[kind].first;
    seen[id] = count + 1;
    p.clout += awarded;
    p.clout_by_source.solo += awarded;
    p.updated_at = new Date().toISOString();
    this._schedule();
    return { awarded };
  }

  setCareer(p, career) {
    p.career = career;
    p.updated_at = new Date().toISOString();
    this._schedule();
  }

  /**
   * Server-only award. body = {room, mode, match_id?, results:[{token|profile_id, won, eliminations, flags, rounds_won}]}
   * Unknown profiles are ignored; a profile is counted once per report; a repeated match_id is ignored.
   */
  applyMatchResult(body) {
    const out = { awarded: [], ignored: 0, duplicate: false };
    if (!body || !Array.isArray(body.results)) return null;
    const matchId = typeof body.match_id === "string" && body.match_id ? body.match_id.slice(0, 80) : "";
    if (matchId) {
      if (this.recentMatches.includes(matchId)) return { ...out, duplicate: true };
      this.recentMatches.push(matchId);
      if (this.recentMatches.length > RECENT_MATCH_IDS) this.recentMatches.shift();
    }
    const seen = new Set();
    for (const raw of body.results.slice(0, MAX_RESULTS_PER_MATCH)) {
      if (!raw || typeof raw !== "object") { out.ignored++; continue; }
      const p = raw.token ? this.byToken(raw.token) : this.profiles.get(String(raw.profile_id || ""));
      if (!p || seen.has(p.id)) { out.ignored++; continue; }
      seen.add(p.id);
      const r = {
        won: raw.won === true,
        eliminations: clampInt(raw.eliminations, MATCH_CAPS.eliminations),
        flags: clampInt(raw.flags, MATCH_CAPS.flags),
        rounds_won: clampInt(raw.rounds_won, MATCH_CAPS.rounds_won),
      };
      const gained = clout(r);
      p.clout += gained;
      p.clout_by_source.online += gained;
      p.stats.matches += 1;
      p.stats.wins += r.won ? 1 : 0;
      p.stats.eliminations += r.eliminations;
      p.stats.flags += r.flags;
      p.stats.rounds_won = (p.stats.rounds_won || 0) + r.rounds_won;
      p.updated_at = new Date().toISOString();
      out.awarded.push({ profile_id: p.id, clout: gained });
    }
    this._schedule();
    return out;
  }
}

const privateView = (p) => ({
  profile_id: p.id, callsign: p.callsign, clout: p.clout, clout_by_source: { ...p.clout_by_source },
  stats: { ...p.stats }, career: p.career, created_at: p.created_at,
});
const publicView = (p) => ({ callsign: p.callsign, clout: p.clout, clout_by_source: { ...p.clout_by_source }, stats: { ...p.stats } });

/** Upgrades older records: clout_by_source defaults to {online: clout, solo: 0}; solo_awards to empty. */
function normalizeProfile(p) {
  p.clout = Math.max(0, Math.floor(Number(p.clout) || 0));
  const cbs = p.clout_by_source;
  if (!cbs || typeof cbs !== "object" || !Number.isFinite(cbs.online) || !Number.isFinite(cbs.solo)) {
    p.clout_by_source = { online: p.clout, solo: 0 };
  }
  const sa = p.solo_awards && typeof p.solo_awards === "object" ? p.solo_awards : {};
  p.solo_awards = {};
  for (const k of Object.keys(SOLO_CLOUT)) p.solo_awards[k] = sa[k] && typeof sa[k] === "object" ? sa[k] : {};
  return p;
}

/** Sliding one-hour window per key. */
class RateLimiter {
  constructor(limit = CREATE_LIMIT_PER_HOUR, windowMs = 3600 * 1000) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.hits = new Map();
  }
  allow(key, now = Date.now()) {
    const arr = (this.hits.get(key) || []).filter((t) => now - t < this.windowMs);
    if (arr.length >= this.limit) { this.hits.set(key, arr); return false; }
    arr.push(now);
    this.hits.set(key, arr);
    if (this.hits.size > 10000) for (const [k, v] of this.hits) if (!v.some((t) => now - t < this.windowMs)) this.hits.delete(k);
    return true;
  }
}

const LOOPBACK = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);

/** Client IP for rate limiting: behind Caddy (loopback peer) use the right-most X-Forwarded-For entry. */
function clientIp(req) {
  const remote = (req.socket && req.socket.remoteAddress) || "";
  const xff = String(req.headers["x-forwarded-for"] || "").split(",").map((s) => s.trim()).filter(Boolean);
  return LOOPBACK.has(remote) && xff.length ? xff[xff.length - 1] : remote;
}

/** Internal calls must come straight from loopback, never through the public proxy, and carry the key. */
function isTrustedInternal(req, internalKey) {
  const remote = (req.socket && req.socket.remoteAddress) || "";
  if (!LOOPBACK.has(remote)) return false;
  if (req.headers["x-forwarded-for"] || req.headers["forwarded"] || req.headers["x-forwarded-host"]) return false;
  const got = Buffer.from(String(req.headers["x-internal-key"] || ""));
  const want = Buffer.from(String(internalKey || ""));
  return want.length > 0 && got.length === want.length && crypto.timingSafeEqual(got, want);
}

function readBody(req, cb) {
  const chunks = [];
  let size = 0;
  let done = false;
  req.on("data", (c) => {
    if (done) return;
    size += c.length;
    if (size > MAX_BODY_BYTES) { done = true; cb("too_large"); req.resume(); return; }
    chunks.push(c);
  });
  req.on("end", () => {
    if (done) return;
    done = true;
    const text = Buffer.concat(chunks).toString("utf8");
    if (!text.trim()) return cb(null, {});
    try { cb(null, JSON.parse(text)); } catch (_) { cb("bad_json"); }
  });
  req.on("error", () => { if (!done) { done = true; cb("bad_json"); } });
}

function bearer(req) {
  const m = /^Bearer\s+([0-9a-fA-F]{64})\s*$/.exec(String(req.headers.authorization || ""));
  return m ? m[1].toLowerCase() : "";
}

/**
 * Handles /api/profile* and /internal/match_result. Returns false if the path is not ours.
 * ctx = {store, internalKey, limiter, cors (headers object), sendJson(res, status, body, headers)}
 */
function handleProfileRequest(req, res, url, ctx) {
  const p = url.pathname;
  const send = (status, body, extra = {}) => ctx.sendJson(res, status, body, { ...ctx.cors, ...extra });

  if (p === "/internal/match_result" || p.startsWith("/internal/")) {
    // /internal/* is loopback-only and never gets CORS headers.
    const send = (status, body, extra = {}) => ctx.sendJson(res, status, body, extra);
    if (p !== "/internal/match_result") return send(404, { error: "not_found" }), true;
    if (req.method !== "POST") return send(405, { error: "method_not_allowed" }, { Allow: "POST" }), true;
    if (!isTrustedInternal(req, ctx.internalKey)) return send(403, { error: "forbidden" }), true;
    readBody(req, (err, body) => {
      if (err) return send(err === "too_large" ? 413 : 400, { error: err });
      const out = ctx.store.applyMatchResult(body);
      if (!out) return send(400, { error: "invalid_body" });
      send(200, out);
    });
    return true;
  }
  if (p !== "/api/profile" && !p.startsWith("/api/profile/")) return false;

  if (req.method === "OPTIONS") {
    res.writeHead(204, ctx.cors);
    res.end();
    return true;
  }

  if (p.startsWith("/api/profile/public/")) {
    if (req.method !== "GET") return send(405, { error: "method_not_allowed" }, { Allow: "GET, OPTIONS" }), true;
    let cs = "";
    try { cs = decodeURIComponent(p.slice("/api/profile/public/".length)); } catch (_) {}
    const prof = ctx.store.byPublicCallsign(cs);
    if (!prof) return send(404, { error: "not_found" }), true;
    return send(200, publicView(prof)), true;
  }

  if (p === "/api/profile" && req.method === "POST") {
    if (!ctx.limiter.allow(clientIp(req))) return send(429, { error: "rate_limited" }, { "Retry-After": "3600" }), true;
    const { profile, token } = ctx.store.create();
    return send(201, { profile_id: profile.id, token, callsign: null, clout: 0, career: null }), true;
  }

  const routes = { "/api/profile": "GET", "/api/profile/callsign": "PUT", "/api/profile/career": "PUT", "/api/profile/solo_award": "POST" };
  if (!routes[p]) return send(404, { error: "not_found" }), true;
  if (req.method !== routes[p]) {
    return send(405, { error: "method_not_allowed" }, { Allow: `${p === "/api/profile" ? "GET, POST" : routes[p]}, OPTIONS` }), true;
  }
  const prof = ctx.store.byToken(bearer(req));
  if (!prof) return send(401, { error: "unauthorized" }, { "WWW-Authenticate": "Bearer" }), true;
  if (p === "/api/profile") return send(200, privateView(prof)), true;
  if (p === "/api/profile/solo_award" && ctx.soloLimiter && !ctx.soloLimiter.allow(prof.id)) {
    return send(429, { error: "rate_limited" }, { "Retry-After": "60" }), true;
  }

  readBody(req, (err, body) => {
    if (err === "too_large") return send(413, { error: "too_large" });
    if (err || !body || typeof body !== "object") return send(400, { error: "bad_json" });
    if (p === "/api/profile/solo_award") {
      const r = ctx.store.soloAward(prof, body.kind, body.id);
      if (r.error) return send(400, { error: r.error });
      return send(200, { awarded: r.awarded, clout: prof.clout, clout_by_source: { ...prof.clout_by_source } });
    }
    if (p === "/api/profile/callsign") {
      const r = ctx.store.setCallsign(prof, body.callsign);
      if (r === "invalid_callsign") return send(400, { error: r });
      if (r === "callsign_taken") return send(409, { error: r });
      return send(200, privateView(prof));
    }
    // career: opaque JSON object (or null to clear), at most 32 KB serialized
    const career = body.career;
    if (career !== null && (typeof career !== "object" || Array.isArray(career))) return send(400, { error: "invalid_career" });
    if (Buffer.byteLength(JSON.stringify(career)) > CAREER_MAX_BYTES) return send(413, { error: "career_too_large" });
    ctx.store.setCareer(prof, career);
    send(200, privateView(prof));
  });
  return true;
}

module.exports = {
  CLOUT, SOLO_CLOUT, SOLO_ID_RE, SOLO_LIMIT_PER_MIN, SOLO_MAX_IDS_PER_KIND, normalizeProfile, MATCH_CAPS, CAREER_MAX_BYTES, CALLSIGN_RE, CREATE_LIMIT_PER_HOUR,
  ProfileStore, RateLimiter, defaultDataDir, clout, sha256, clientIp, isTrustedInternal, handleProfileRequest,
  privateView, publicView,
};
