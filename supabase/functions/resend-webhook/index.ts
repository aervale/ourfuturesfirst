// Resend calls this each time an email is sent, delivered, delayed, bounced, reported as spam, or fails.
// It passes the request, exactly as it arrived, to the database function mail_event(), which checks Resend's
// signature and stores the event (supabase/migrations/*_mail_events.sql). The admin page reads them back.
// Resend signs its own requests, so no Supabase login is asked for ([functions.resend-webhook] in config.toml).
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

Deno.serve(async request => {
	if (request.method !== 'POST') return new Response('Our Futures First email events', { status: 200 });
	const body = await request.text();
	if (body.length > 200_000) return new Response('Too large', { status: 413 });
	const header = (name: string) => request.headers.get(name) ?? '';
	const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mail_event`, {
		method: 'POST',
		headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, 'content-type': 'application/json' },
		body: JSON.stringify({ p_svix_id: header('svix-id'), p_ts: header('svix-timestamp'), p_sig: header('svix-signature'), p_body: body })
	});
	const result = response.ok ? await response.json() : 'error';
	if (result === 'ok') return new Response('ok', { status: 200 });
	if (result === 'bad_signature' || result === 'stale') return new Response(result, { status: 401 });
	// anything else (no secret yet, database trouble): a 500 makes Resend try again later
	console.error('mail_event:', result, response.status);
	return new Response('not stored', { status: 500 });
});
