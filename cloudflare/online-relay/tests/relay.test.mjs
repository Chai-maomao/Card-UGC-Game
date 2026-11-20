import { test } from "node:test";
import assert from "node:assert/strict";
import { relay } from "../src/relay.ts";
import { database } from "./sqlite-adapter.mjs";

test("room authorization, atomic join, binary relay, retry dedup, reset, expiry and cleanup", async () => {
  const db = database();
  async function call(path, data = {}, token = "") {
    const response = await relay(new Request("http://localhost/api/" + path, { method: "POST", headers: { "Content-Type": "application/json", "Authorization": "Bearer " + token }, body: JSON.stringify(data) }), db);
    return { status: response.status, ...await response.json() };
  }
  assert.equal((await call("rooms", { protocol: 0 })).status, 426);
  const host = await call("rooms", { protocol: 1 });
  assert.equal(host.status, 201); assert.match(host.code, /^[A-F0-9]{8}$/);
  const root = "rooms/" + host.code + "/";
  const joins = await Promise.all([call(root + "join", { protocol: 1 }), call(root + "join", { protocol: 1 })]);
  assert.deepEqual(joins.map(x => x.status).sort(), [200, 409]);
  const guest = joins.find(x => x.status === 200);
  assert.notEqual(host.token, guest.token);
  assert.equal((await call(root + "attach", { instance: "a".repeat(32) }, "0".repeat(64))).status, 401);
  const h = await call(root + "attach", { instance: "a".repeat(32) }, host.token);
  const g = await call(root + "attach", { instance: "b".repeat(32) }, guest.token);
  assert.equal((await call(root + "exchange", { generation: h.generation, after: 0, packets: [] }, host.token)).error, "generation_changed");
  const generation = (await call(root + "attach", { instance: "a".repeat(32) }, host.token)).generation;
  assert.equal(generation, g.generation);
  const packet = { sequence: 1, channel: 1, mode: 2, data: Buffer.from([0,255,0,128,42]).toString("base64") };
  const send = () => call(root + "exchange", { generation, after: 0, packets: [packet] }, host.token);
  assert.equal((await send()).present, true); await send();
  const received = await call(root + "exchange", { generation, after: 0, packets: [] }, guest.token);
  assert.equal(received.packets.length, 1); assert.equal(received.packets[0].data, packet.data);
  const after = received.packets[0].id;
  await call(root + "exchange", { generation, after, packets: [] }, guest.token);
  await send(); // Lost POST response retried after the opponent has acknowledged.
  assert.equal((await call(root + "exchange", { generation, after, packets: [] }, guest.token)).packets.length, 0);
  assert.equal((await call(root + "exchange", { generation, after: 0, packets: [{ ...packet, channel: 99 }] }, host.token)).status, 400);
  const next = await call(root + "attach", { instance: "c".repeat(32) }, host.token);
  assert.ok(next.generation > generation);
  assert.equal((await call(root + "exchange", { generation, after: 0, packets: [] }, guest.token)).status, 409);
  assert.equal((await call(root + "leave", {}, guest.token)).closed, true);
  assert.equal((await call(root + "join", { protocol: 1 })).status, 404);
  assert.equal(db.sqlite.prepare("SELECT COUNT(*) AS n FROM packets").get().n, 0);
  const expired = await call("rooms", { protocol: 1 });
  db.sqlite.prepare("UPDATE rooms SET expires=0 WHERE code=?").run(expired.code);
  assert.equal((await call("rooms/" + expired.code + "/attach", { instance: "d".repeat(32) }, expired.token)).error, "room_expired");
  db.sqlite.close();
});
