// lib/email.ts
import { supabase } from "./supabase";

type SendInviteArgs = {
  to: string | string[];
  eventUrl?: string;
  joinCode?: string;

  // either (or neither) — date-only is fine
  eventDate?: string;           // "YYYY-MM-DD"
  eventStartsAtISO?: string;    // full ISO if you ever add time

  eventTimezone?: string;
  locationText?: string;
  messageFromInviter?: string;
  inviterName: string;
  recipientName?: string;
  brand?: {
    appName?: string;
    logoUrl?: string;
    primary?: string;
    footerAddress?: string;
  };
};

export type SendInviteResult =
  | { ok: true; id: string | null }
  | { ok: false; error: string };

export async function sendInviteEmail(args: SendInviteArgs): Promise<SendInviteResult> {
  try {
    const { data, error } = await supabase.functions.invoke("send-invite-email", { body: args });

    if (error) {
      // error.context is a fetch Response; read its JSON/text to show the server error
      const ctx: any = (error as any).context;
      let msg = (error as any)?.message || "Function call failed";
      if (ctx && typeof ctx.json === "function") {
        try {
          const j = await ctx.json();
          msg = j?.error || j?.message || JSON.stringify(j);
        } catch {
          try {
            const t = await ctx.text?.();
            if (t) msg = t;
          } catch {}
        }
      }
      console.error("send-invite-email invoke error:", msg);
      return { ok: false, error: msg };
    }

    if (!data?.ok) {
      const msg = data?.error || "Function returned non-ok";
      return { ok: false, error: msg };
    }
    return { ok: true, id: data?.id ?? null };
  } catch (e: any) {
    return { ok: false, error: e?.message || String(e) };
  }
}
