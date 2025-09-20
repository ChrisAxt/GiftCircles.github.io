// supabase/functions/delete-account/index.ts
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...cors } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { ok: false, error: "Method Not Allowed" });

  try {
    const auth = req.headers.get("Authorization") || "";
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url) throw new Error("Missing SUPABASE_URL");
    if (!anon) throw new Error("Missing SUPABASE_ANON_KEY");
    if (!service) throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY");
    if (!auth.startsWith("Bearer ")) return json(401, { ok: false, error: "Missing bearer token" });

    // 1) Verify token → get current user id
    const meRes = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: auth, apikey: anon } });
    const me = await meRes.json();
    if (!meRes.ok || !me?.id) return json(401, { ok: false, error: "Invalid or expired session token" });
    const uid: string = me.id;

    // 2) Best-effort cleanup of app data
    const srvHeaders = {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    };
    await Promise.allSettled([
      fetch(`${url}/rest/v1/claims?user_id=eq.${uid}`, { method: "DELETE", headers: srvHeaders }),
      fetch(`${url}/rest/v1/event_members?user_id=eq.${uid}`, { method: "DELETE", headers: srvHeaders }),
      fetch(`${url}/rest/v1/list_recipients?user_id=eq.${uid}`, { method: "DELETE", headers: srvHeaders }),
      fetch(`${url}/rest/v1/profiles?id=eq.${uid}`, { method: "DELETE", headers: srvHeaders }),
    ]);

    // 3) Delete Auth user (hard delete)
    const delRes = await fetch(`${url}/auth/v1/admin/users/${uid}`, {
      method: "DELETE",
      headers: { apikey: service, Authorization: `Bearer ${service}` },
    });
    if (!delRes.ok) {
      const t = await delRes.text();
      throw new Error(`Auth delete failed: ${t || delRes.status}`);
    }

    return json(200, { ok: true });
  } catch (err) {
    console.error("delete-account failed:", err);
    return json(400, { ok: false, error: String(err) });
  }
});
