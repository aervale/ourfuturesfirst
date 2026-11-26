/* Backend connection. On your own machine the page talks to the local database (supabase start);
   anywhere else it talks to the hosted Supabase project. Both keys are publishable ones, safe to ship in a page.
   Leave url empty to run the page in preview mode with sample data. */
window.OFF_CONFIG=/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname)?{
  url:"http://127.0.0.1:54421",
  key:"sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  /* Cloudflare Turnstile site key for the spam check. This is Cloudflare's test key, which always passes. */
  turnstile:"1x00000000000000000000BB",
  /* Local test mode: admin.html opens without signing in.
     It only works against the local database (see supabase/seed.sql). */
  dev:true
}:{
  url:"https://pexnchjiphwyftvhykih.supabase.co",
  key:"sb_publishable_i-3pCBiKdA94E52wiPQ9iA_WxLqp6y1",
  /* Cloudflare Turnstile site key (public) for the "Our Futures First sign-up" widget. Its secret key goes in
     Supabase: Authentication > Attack Protection > Captcha, provider Turnstile. */
  turnstile:"0x4AAAAAAGUXpCs3DKLRjllg"
};
