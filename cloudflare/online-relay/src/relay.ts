// All durable room state lives in D1, never in Worker process memory.
type Statement = { bind(...args: unknown[]): Statement; first<T = Record<string, unknown>>(): Promise<T | null>; all(): Promise<{ results: any[] }>; run(): Promise<any> };
export type Database = { prepare(sql: string): Statement; batch(statements: Statement[]): Promise<any[]> };
type Room = { code: string; host: string; guest: string | null; generation: number; expires: number; [key: string]: any };
const TTL = 60 * 60 * 1000;
const MAX_BODY = 512 * 1024;
const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
const fail = (error: string, status = 400) => json({ error }, status);
const random = (n: number) => Array.from(crypto.getRandomValues(new Uint8Array(n)), x => x.toString(16).padStart(2, "0")).join("");
async function hash(value: string) { return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), x => x.toString(16).padStart(2, "0")).join(""); }
async function readBody(request: Request) {
  if (Number(request.headers.get("content-length")) > MAX_BODY) throw new Error("payload_too_large");
  const reader = request.body?.getReader(); if (!reader) return {};
  let size = 0; const chunks: Uint8Array[] = [];
  while (true) {
    const part = await reader.read(); if (part.done) break;
    size += part.value.length;
    if (size > MAX_BODY) { await reader.cancel(); throw new Error("payload_too_large"); }
    chunks.push(part.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const data = JSON.parse(new TextDecoder().decode(bytes));
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_json");
  return data;
}
export async function relay(request: Request, db: Database): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (path === "/api/health" && request.method === "GET") {
    await db.prepare("SELECT 1 AS ok").first();
    return json({ service: "cardex-relay", version: 1, transport: "https-poll", room_ttl_seconds: TTL / 1000 });
  }
  if (request.method !== "POST") return fail("method_not_allowed", 405);
  let data: any;
  try { data = await readBody(request); } catch (e) { return fail(e instanceof Error && e.message === "payload_too_large" ? "payload_too_large" : "invalid_json"); }
  const now = Date.now();
  if (path === "/api/rooms") {
    if (data.protocol !== 1) return fail("protocol_mismatch", 426);
    const creator = await hash(request.headers.get("cf-connecting-ip") ?? "local");
    const token = random(32), code = random(4).toUpperCase();
    await db.prepare("DELETE FROM rooms WHERE expires < ?").bind(now).run();
    const result = await db.prepare("INSERT INTO rooms (code,host,creator,expires) SELECT ?,?,?,? WHERE (SELECT COUNT(*) FROM rooms)<32 AND (SELECT COUNT(*) FROM rooms WHERE creator=?)<4").bind(code, await hash(token), creator, now + TTL, creator).run();
    if (!result.meta?.changes) return fail("capacity_reached", 429);
    return json({ code, token, player: 1, expires: now + TTL }, 201);
  }
  const match = /^\/api\/rooms\/([A-F0-9]{8})\/(join|attach|exchange|leave)$/.exec(path);
  if (!match) return fail("not_found", 404);
  const [, code, action] = match;
  let room = await db.prepare("SELECT * FROM rooms WHERE code=? AND expires>?").bind(code, now).first<Room>();
  if (!room) return fail("room_expired", 404);
  if (action === "join") {
    if (data.protocol !== 1) return fail("protocol_mismatch", 426);
    const token = random(32);
    const result = await db.prepare("UPDATE rooms SET guest=? WHERE code=? AND guest IS NULL AND expires>?").bind(await hash(token), code, now).run();
    return result.meta?.changes ? json({ code, token, player: 2, expires: room.expires }) : fail("room_full", 409);
  }
  const token = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  if (!/^[a-f0-9]{64}$/.test(token)) return fail("unauthorized", 401);
  const digest = await hash(token);
  const player = digest === room.host ? 1 : digest === room.guest ? 2 : 0;
  if (!player) return fail("unauthorized", 401);
  const other = 3 - player;
  if (action === "leave") {
    await db.prepare("DELETE FROM rooms WHERE code=?").bind(code).run();
    return json({ closed: true });
  }
  if (action === "attach") {
    if (typeof data.instance !== "string" || !/^[a-f0-9]{32}$/.test(data.instance)) return fail("invalid_instance");
    // A new transport invalidates both clients' RPC path caches. A remote reset
    // reattaches with its previous instance to avoid a generation reset loop.
    await db.batch([
      db.prepare(`UPDATE rooms SET generation=generation+1, instance${player}=?, ready1=-1, ready2=-1, accepted1=0, accepted2=0 WHERE code=? AND instance${player}<>?`).bind(data.instance, code, data.instance),
      db.prepare(`UPDATE rooms SET ready${player}=generation, seen${player}=? WHERE code=?`).bind(now, code),
    ]);
    room = (await db.prepare("SELECT * FROM rooms WHERE code=?").bind(code).first<Room>())!;
    await db.prepare("DELETE FROM packets WHERE room=? AND generation<>?").bind(code, room.generation).run();
    return json({ generation: room.generation, cursor: 0 });
  }
  if (data.generation !== room.generation) return json({ error: "generation_changed", generation: room.generation }, 409);
  if (!Number.isSafeInteger(data.after) || data.after < 0 || !Array.isArray(data.packets) || data.packets.length > 16) return fail("invalid_packets");
  for (const p of data.packets) {
    if (!p || !Number.isSafeInteger(p.sequence) || p.sequence <= 0 || !Number.isInteger(p.channel) || p.channel < 0 || p.channel > 4 || ![0, 1, 2].includes(p.mode) || typeof p.data !== "string" || p.data.length > 256 * 1024 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(p.data)) return fail("invalid_packets");
  }
  const queued = await db.prepare("SELECT COUNT(*) AS n,COALESCE(SUM(LENGTH(data)),0) AS bytes FROM packets WHERE room=? AND generation=? AND sender=?").bind(code, room.generation, player).first<{ n: number; bytes: number }>();
  if ((queued?.n ?? 0) + data.packets.length > 512 || (queued?.bytes ?? 0) + data.packets.reduce((n: number, p: any) => n + p.data.length, 0) > 8 * 1024 * 1024) return fail("mailbox_full", 429);
  const statements = [
    db.prepare(`UPDATE rooms SET seen${player}=? WHERE code=?`).bind(now, code),
    db.prepare("DELETE FROM packets WHERE room=? AND generation=? AND sender=? AND id<=?").bind(code, room.generation, other, data.after),
    ...data.packets.map((p: any) => db.prepare(`INSERT OR IGNORE INTO packets (room,generation,sender,sequence,channel,mode,data) SELECT ?,?,?,?,?,?,? WHERE ?>? AND EXISTS (SELECT 1 FROM rooms WHERE code=? AND generation=?)`).bind(code, room.generation, player, p.sequence, p.channel, p.mode, p.data, p.sequence, room[`accepted${player}`], code, room.generation)),
    db.prepare(`UPDATE rooms SET accepted${player}=MAX(accepted${player},?) WHERE code=? AND generation=?`).bind(Math.max(0, ...data.packets.map((p: any) => p.sequence)), code, room.generation),
    db.prepare("SELECT id,channel,mode,data FROM packets WHERE room=? AND generation=? AND sender=? AND id>? ORDER BY id LIMIT 16").bind(code, room.generation, other, data.after),
    db.prepare("SELECT generation FROM rooms WHERE code=?").bind(code),
  ];
  const result = await db.batch(statements);
  if (result.at(-1).results[0]?.generation !== room.generation) return json({ error: "generation_changed" }, 409);
  return json({ generation: room.generation, present: room[`ready${other}`] === room.generation && room[`seen${other}`] > now - 15000, packets: result.at(-2).results, expires: room.expires });
}
