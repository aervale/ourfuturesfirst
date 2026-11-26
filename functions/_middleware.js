/* Testing gate: the whole site asks for one shared password until launch.
   Delete this file to make the site public.

   The password itself is not in this repository. PASS is the SHA-256 of the password,
   and KEY is the SHA-256 of the cookie a visitor gets after typing it, where that cookie is
   SHA-256("cookie:" + password). Neither can be turned back into the password or the cookie. */
const PASS = "3de13649d544fb267b75c1369f0b6a7fc0336c35f1c985831ca35612b6c0c80e";
const KEY = "7b988bbe7094e0c8be30d232db0a3008780bf1a0f0ad3f6214289bfd28c1c26e";
const COOKIE = "off_gate";
const DAYS = 30;

async function sha(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function cookieOf(request) {
  const m = (request.headers.get("Cookie") || "").match(new RegExp("(?:^|;\\s*)" + COOKIE + "=([0-9a-f]{64})"));
  return m ? m[1] : "";
}

function page(wrong) {
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Our Futures First</title>
<link href="https://fonts.googleapis.com/css2?family=EB+Garamond:wght@500&family=Nunito+Sans:wght@400;600&display=swap" rel="stylesheet">
<style>
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0C0C0E;color:#ECEAE0;font-family:"Nunito Sans",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
main{width:min(360px,100% - 32px)}
.eye{font-size:12px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:#C8463F}
h1{font-family:"EB Garamond",Georgia,serif;font-weight:500;font-size:30px;line-height:1.15;margin:10px 0 8px}
p{margin:0 0 20px;color:rgba(236,234,224,.62);line-height:1.5}
input{box-sizing:border-box;width:100%;padding:12px 14px;border-radius:6px;border:1px solid rgba(236,234,224,.16);background:#151517;color:inherit;font:inherit;font-size:16px}
input:focus{outline:0;border-color:#A22C29}
button{margin-top:12px;width:100%;padding:12px;border:0;border-radius:6px;background:#A22C29;color:#ECEAE0;font:inherit;font-weight:600;letter-spacing:.08em;text-transform:uppercase;font-size:13px;cursor:pointer}
.err{color:#E0645C;font-size:14px;margin:10px 0 0}
</style></head><body><main>
<div class="eye">Our Futures First</div>
<h1>This site is being tested</h1>
<p>Enter the password you were given.</p>
<form method="post"><input type="password" name="password" autocomplete="current-password" autofocus aria-label="Password">
<button type="submit">Enter</button>${wrong ? '<p class="err">That password is not right.</p>' : ""}</form>
</main></body></html>`;
  return new Response(html, {
    status: 401,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex" },
  });
}

export async function onRequest(ctx) {
  const { request } = ctx;
  const c = cookieOf(request);
  if (c && (await sha(c)) === KEY) return ctx.next();

  if (request.method === "POST") {
    let pw = "";
    try { pw = String((await request.formData()).get("password") || ""); } catch (e) {}
    if (pw && (await sha(pw)) === PASS) {
      const value = await sha("cookie:" + pw);
      // back to the same address, query string included, so email links still work after the password
      return new Response(null, {
        status: 303,
        headers: {
          Location: new URL(request.url).pathname + new URL(request.url).search,
          "Set-Cookie": `${COOKIE}=${value}; Path=/; Max-Age=${DAYS * 86400}; HttpOnly; Secure; SameSite=Lax`,
          "Cache-Control": "no-store",
        },
      });
    }
    return page(true);
  }
  return page(false);
}
