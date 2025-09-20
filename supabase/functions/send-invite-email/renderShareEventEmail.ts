type ShareEventEmailData = {
  recipientName?: string;
  inviterName: string;
  eventName: string;
  eventDate?: string;        // YYYY-MM-DD
  eventStartsAtISO?: string; // optional
  eventTimezone?: string;
  locationText?: string;
  messageFromInviter?: string;
  eventUrl: string;
  brand?: { appName?: string; logoUrl?: string; primary?: string; footerAddress?: string };
};

function formatDateOnly(dateYYYYMMDD: string, tz: string) {
  const d = new Date(`${dateYYYYMMDD}T12:00:00Z`); // noon to avoid tz rollovers
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "long", day: "numeric", month: "short", year: "numeric", timeZone: tz,
  }).format(d);
}
function formatDateTime(iso: string, tz: string) {
  const d = new Date(iso);
  const dateStr = new Intl.DateTimeFormat("en-GB", {
    weekday: "long", day: "numeric", month: "short", year: "numeric", timeZone: tz,
  }).format(d);
  const timeStr = new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit", minute: "2-digit", hour12: false, timeZone: tz,
  }).format(d);
  return { dateStr, timeStr };
}

export function renderShareEventEmail(data: ShareEventEmailData) {
  const tz = data.eventTimezone || "Europe/Stockholm";
  const primary = data.brand?.primary || "#4F46E5";
  const appName = data.brand?.appName || "GiftCircles";

  let whenLine: string | undefined;
  let dateForSubject: string | undefined;

  if (data.eventDate) {
    const dateStr = formatDateOnly(data.eventDate, tz);
    whenLine = `${dateStr}`;
    dateForSubject = dateStr;
  } else if (data.eventStartsAtISO) {
    const { dateStr, timeStr } = formatDateTime(data.eventStartsAtISO, tz);
    whenLine = `${dateStr} at ${timeStr} (${tz})`;
    dateForSubject = dateStr;
  }

  const safe = (s?: string) => (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const preheader = whenLine
    ? `${data.inviterName} invited you to ${data.eventName} — ${whenLine}`
    : `${data.inviterName} invited you to ${data.eventName}`;
  const subject = dateForSubject
    ? `You're invited: ${data.eventName} — ${dateForSubject}`
    : `You're invited: ${data.eventName}`;

  const text = [
    data.recipientName ? `Hi ${data.recipientName},` : `Hi,`,
    ``,
    `${data.inviterName} invited you to “${data.eventName}”.`,
    whenLine ? `When: ${whenLine}` : ``,
    data.locationText ? `Where: ${data.locationText}` : ``,
    data.messageFromInviter ? `Message: ${data.messageFromInviter}` : ``,
    ``,
    `Open the invite: ${data.eventUrl}`,
    ``,
    `${appName}`,
  ].filter(Boolean).join("\n");

  const whenBlock = whenLine
    ? `
      <tr><td style="font:600 14px -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;padding:0 0 4px;">When</td></tr>
      <tr><td class="muted" style="font:500 14px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#374151;">${safe(whenLine)}</td></tr>
    `
    : ``;

  const html = `<!doctype html><html lang="en" xmlns="http://www.w3.org/1999/xhtml"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>${subject}</title>
<style>
@media (prefers-color-scheme: dark) {
  .bg { background:#0b0f19 !important; }
  .card { background:#111827 !important; color:#e5e7eb !important; }
  .muted { color:#9ca3af !important; }
  .btn a { color:#ffffff !important; }
}
a { text-decoration:none; }
</style>
</head>
<body class="bg" style="margin:0;padding:0;background:#f5f7fb;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f7fb;">
<tr><td align="center" style="padding:32px 16px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;">
    <tr>
      <td align="left" style="padding:8px 12px;">
        ${data.brand?.logoUrl
          ? `<img alt="${appName}" src="${data.brand.logoUrl}" height="28" style="display:block;border:0;outline:none;">`
          : `<div style="font:600 18px/1.2 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;">${appName}</div>`}
      </td>
    </tr>
    <tr>
      <td class="card" style="background:#ffffff;border-radius:14px;padding:24px 24px 8px;box-shadow:0 6px 20px rgba(0,0,0,0.06);">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          <tr>
            <td style="font:700 22px/1.25 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;padding:4px 0 8px;">
              You’re invited to <span style="color:${primary}">${safe(data.eventName)}</span>
            </td>
          </tr>
          <tr>
            <td class="muted" style="font:500 14px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#6b7280;padding:0 0 16px;">
              from ${safe(data.inviterName)}
            </td>
          </tr>
          <tr><td style="padding:12px 0 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              ${whenBlock}
              ${data.locationText ? `
              <tr><td style="height:12px;"></td></tr>
              <tr><td style="font:600 14px -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;padding:0 0 4px;">Where</td></tr>
              <tr><td class="muted" style="font:500 14px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#374151;">${safe(data.locationText)}</td></tr>` : ``}
              ${data.messageFromInviter ? `
              <tr><td style="height:12px;"></td></tr>
              <tr><td style="font:600 14px -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;padding:0 0 4px;">Message from ${safe(data.inviterName)}</td></tr>
              <tr><td class="muted" style="font:500 14px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#374151;">${safe(data.messageFromInviter)}</td></tr>` : ``}
              <tr><td style="height:20px;"></td></tr>
              <tr>
                <td align="left" class="btn" style="padding:0 0 8px;">
                  <a href="${data.eventUrl}" style="display:inline-block;background:${primary};color:#ffffff;border-radius:10px;padding:12px 18px;font:700 14px -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">View invitation</a>
                </td>
              </tr>
              <tr>
                <td class="muted" style="font:500 12px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#6b7280;padding:6px 0 0;">
                  If the button doesn’t work, copy and paste this link:<br>
                  <a href="${data.eventUrl}" style="word-break:break-all;">${data.eventUrl}</a>
                </td>
              </tr>
              <tr><td style="height:8px;"></td></tr>
            </table>
          </td></tr>
        </table>
      </td>
    </tr>
    <tr>
      <td align="left" style="padding:14px 8px 0;color:#6b7280;font:500 12px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        You received this because someone shared an event with you in ${appName}.
        ${data.brand?.footerAddress ? `<div style="margin-top:6px;">${safe(data.brand.footerAddress)}</div>` : ``}
      </td>
    </tr>
    <tr><td style="height:18px;"></td></tr>
  </table>
</td></tr>
</table>
</body></html>`;

  return { subject, html, text, preheader };
}
