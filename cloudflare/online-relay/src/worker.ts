import { relay } from "./relay";
type Env = { DB?: D1Database; BETA_DISABLED?: string };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
    if (env.BETA_DISABLED === "1") return json({ error: "service_unavailable" }, 503);
    if (new URL(request.url).pathname === "/") {
      return json({ service: "cardex-relay", provider: "Cloudflare Workers", protocol: 1, health: "/api/health" });
    }
    if (!env.DB) return json({ error: "service_unavailable" }, 503);
    try { return await relay(request, env.DB); }
    catch { return json({ error: "service_unavailable" }, 503); }
  },
};
