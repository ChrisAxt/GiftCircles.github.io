// supabase/functions/send-invite-email/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { renderShareEventEmail } from "./renderShareEventEmail.ts";

const TEST_MODE = Deno.env.get("RESEND_TEST_MODE") === "true";
const FROM = Deno.env.get("INVITE_FROM_EMAIL") || "GiftCircles <onboarding@resend.dev>";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Payload = {
  to: string | string[];
  eventUrl?: string;
  joinCode?: string;
  eventName: string;

  // Either (or neither): date-only or full datetime
  eventDate?: string;        // YYYY-MM-DD (optional)
  eventStartsAtISO?: string; // optional

  eventTimezone?: string;
  locationText?: string;
  messageFromInviter?: string;
  inviterName: string;
  recipientName?: string;
  brand?: { appName?: string; logoUrl?: string; primary?: string; footerAddress?: string };
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: cors });

  try {
    const payload = (await req.json()) as Payload;

    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
    if (!RESEND_API_KEY) throw new Error("Missing RESEND_API_KEY");
    if (!FROM) throw new Error("Missing INVITE_FROM_EMAIL");

    // Build event URL from joinCode if not provided
    const eventUrl =
      payload.eventUrl ??
      (payload.joinCode ? `https://giftcircles.app/join?code=${encodeURIComponent(payload.joinCode)}` : undefined);
    if (!eventUrl) throw new Error("Provide 'eventUrl' or 'joinCode'");

    // Required fields
    if (!payload.to) throw new Error("Missing 'to'");
    if (!payload.eventName) throw new Error("Missing 'eventName'");
    if (!payload.inviterName) throw new Error("Missing 'inviterName'");

    // Render email (handles eventDate OR eventStartsAtISO OR neither)
    const { subject, html, text, preheader } = renderShareEventEmail({ ...payload, eventUrl });

    // In TEST_MODE, always route to Resend's test inbox so you can send without a domain
    const toRecipients: string | string[] = TEST_MODE
      ? (Array.isArray(payload.to)
          ? payload.to.map((_t, i) => `delivered+${i}-${crypto.randomUUID().slice(0, 8)}@resend.dev`)
          : `delivered+${crypto.randomUUID().slice(0, 8)}@resend.dev`)
      : payload.to;

    // Send via Resend HTTP API (SDK-free)
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM,                 // e.g. "GiftCircles <onboarding@resend.dev>" in TEST_MODE
        to: toRecipients,           // test inboxes if TEST_MODE=true
        subject,
        html,
        text,
        headers: { "X-Preheader": preheader },
      }),
    });

    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      const raw = j?.error?.message || JSON.stringify(j) || `HTTP ${r.status}`;
      throw new Error(`Resend API error: ${raw}`);
    }

    return new Response(JSON.stringify({ ok: true, id: j?.id ?? null }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...cors },
    });
  } catch (err) {
    console.error("send-invite-email failed:", err);
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }
});
