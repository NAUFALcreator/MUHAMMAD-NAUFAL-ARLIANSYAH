// Edge Function: kirim notifikasi (WhatsApp -> SMS -> Email, failover) dan webhook bertanda tangan HMAC-SHA256
// Env: WA_PHONE_ID, WA_TOKEN, TWILIO_SID, TWILIO_TOKEN, TWILIO_FROM, RESEND_KEY, MAIL_FROM
import { createClient } from "npm:@supabase/supabase-js@2";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const env = (k: string) => Deno.env.get(k) ?? "";

async function hmac(secret: string, body: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const s = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(body));
  return [...new Uint8Array(s)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const ok = (r: Response, n: string) => { if (!r.ok) throw new Error(`${n} ${r.status}`); };

const providers: Record<string, (to: string, text: string) => Promise<void>> = {
  whatsapp: async (to, text) => ok(await fetch(`https://graph.facebook.com/v20.0/${env("WA_PHONE_ID")}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${env("WA_TOKEN")}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to, type: "text", text: { body: text } })
  }), "wa"),
  sms: async (to, text) => ok(await fetch(`https://api.twilio.com/2010-04-01/Accounts/${env("TWILIO_SID")}/Messages.json`, {
    method: "POST", headers: { Authorization: "Basic " + btoa(`${env("TWILIO_SID")}:${env("TWILIO_TOKEN")}`) },
    body: new URLSearchParams({ To: to, From: env("TWILIO_FROM"), Body: text })
  }), "sms"),
  email: async (to, text) => ok(await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${env("RESEND_KEY")}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env("MAIL_FROM"), to, subject: "QueueFlow", text })
  }), "mail"),
};

async function send(to: string, text: string) {
  const order = to.includes("@") ? ["email"] : ["whatsapp", "sms"];
  let err = "";
  for (const p of order) { try { await providers[p](to, text); return; } catch (e) { err = String(e); } }
  throw new Error(err);
}

Deno.serve(async () => {
  const { data: jobs } = await sb.from("outbox").select("*").eq("status", "pending").lte("next_at", new Date().toISOString()).order("id").limit(50);
  let sent = 0;
  for (const j of jobs ?? []) {
    try {
      if (j.kind === "notify") await send(j.target, j.payload.text);
      else {
        const { data: w } = await sb.from("webhooks").select("*").eq("id", j.target).single();
        if (!w) throw new Error("webhook hilang");
        const body = JSON.stringify(j.payload);
        const r = await fetch(w.url, { method: "POST", headers: { "Content-Type": "application/json",
          "X-QueueFlow-Signature": await hmac(w.secret, body) }, body });
        ok(r, "webhook");
      }
      await sb.from("outbox").update({ status: "sent" }).eq("id", j.id); sent++;
    } catch (e) {
      const a = j.attempts + 1;  // exponential back-off: 1m, 2m, 4m, ...
      await sb.from("outbox").update({ attempts: a, last_error: String(e), status: a >= 6 ? "failed" : "pending",
        next_at: new Date(Date.now() + 60000 * 2 ** (a - 1)).toISOString() }).eq("id", j.id);
    }
  }
  return new Response(JSON.stringify({ sent }), { headers: { "Content-Type": "application/json" } });
});
