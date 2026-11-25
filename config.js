/* Backend connection. These are the local development values (supabase start).
   Leave url empty to run the page in preview mode with sample data. */
window.OFF_CONFIG={
  url:"http://127.0.0.1:54421",
  key:"sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  /* Cloudflare Turnstile site key for the spam check. This is Cloudflare's test key, which always passes. */
  turnstile:"1x00000000000000000000BB",
  /* Local test mode: a sign-up is confirmed at once with no email, and admin.html opens without signing in.
     It only works against the local database (see supabase/seed.sql). Remove this line before launch. */
  dev:true
};
