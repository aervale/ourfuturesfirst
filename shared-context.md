# Shared context

What David, April and their Claude sessions need to know that the code does not say: decisions, how live is
changed, pitfalls, and open questions. Read it before starting work. Update it in the same commit as the change
that makes it true.

**This repository is public** on GitHub (the site itself serves only its own files). Never put emails, tokens, passwords, people's names or anything private here.

## How to keep this file

- One line per item where possible, with the date (YYYY-MM-DD) and who decided or found it.
- Decisions go in **Decisions**; questions waiting on David or April go in **Open**. When one is answered, move it
  to Decisions.
- Delete items that stop being true. Do not keep history here; git has it.
- Pull before editing and push straight after (`git fetch && git rebase origin/main`, then `git push origin HEAD:main`).
  Both sessions edit this file, so keep each change small to make conflicts easy.

## Working together

- Everything lands on `main`. Fetch and rebase before every push; push small commits often.
- Live must match `main`. If you change live, the repo change is pushed in the same sitting, and the other way round.
- Each person keeps their own copy of the bot token, outside git. Never reset the token: it breaks the live bot.

## Changing live

- **Database:** write the migration file in `supabase/migrations/` first, commit it, then apply it to live.
  Use `apply_migration` (Supabase MCP), or run the file and record it in `supabase_migrations.schema_migrations`
  under the file's own version. Never run plain SQL that is not in a file.
- **Never run `supabase db push`.** Live's migration history mixes the files' versions with timestamps that
  `apply_migration` chose (for example `admin_discord` is 20261128052919 on live, 20261128000500 in the repo), so
  `db push` would try to re-run nearly everything. Match migrations by **name**, not version.
- **Naming a migration:** start the file name with a fresh timestamp (`YYYYMMDDHHMMSS`), not the next small
  number: two sessions picking "the next number" collided once (2026-11-28, April's session).
- **Running a file without the MCP** (April's session, CLI 3.x): `supabase db query --remote=pexnchjiphwyftvhykih --yes -f <file>`,
  then insert `(version, name, statements)` into `supabase_migrations.schema_migrations`. `--read-only` for looking.
- **Bot:** after changing `supabase/functions/discord/`, redeploy the `discord` function (verify JWT off: Discord
  signs its own requests) and say the new version number in the commit or here. CLI:
  `supabase functions deploy discord --remote=pexnchjiphwyftvhykih --no-verify-jwt --use-api --yes`.
- **Confirmation email:** the live template is set by hand in the Supabase dashboard (Authentication > Emails >
  Confirm sign up). `supabase/templates/confirm.html` is the copy in the repo: change both, paste the file's whole
  text. Only HTML can be set there; the plain-text part is generated from it on the way out.
- **Discord server:** `node --env-file=<your env file> discord/setup.mjs`. Safe to re-run: it finds things by
  name and only adds or corrects.

## Decisions

- 2026-11-28 David: still a gated, limited preview. The password gate (`functions/_middleware.js`) and
  Cloudflare Access stay on. Page switches on live are all off except Discord.
- 2026-11-28 David: Discord is the main way we talk with everyone who signs up, and where the core team
  coordinates (#team-chat, core team only).
- 2026-11-28 David, April: Discord roles follow the sign-up. Everyone who confirms a university email gets
  **Member**; only people whose confirmed sign-up offered to organize also get **Organizer**.
- 2026-11-28 David: named links (`?l=`) are made only by the core team on the admin page and handed out.
- 2026-11-28 David: no per-university "in charge" or coordinator on the admin page.
- 2026-11-28 David: blocking unsuitable names uses the word list only; no outside screening service.
- 2026-11-28 David, April: every live change goes through a migration file in the repo.
- 2026-11-28 April: "Remove me" is counted (`removals`: date, university, whether confirmed, hours since
  signing up; nothing that identifies the person) and shown on the admin page. The privacy page says so.
- 2026-11-28 David: the site serves only its own files, gated or not. `functions/_middleware.js` answers 404 for
  everything else in the repo. A new file the pages use must be added to its `SITE` list (or live under `assets/`).
  To go public, set `GATED = false` there; never delete the file, or the whole repo is served.
- 2026-11-28 David: link previews (iMessage and others) show the gold star with "AI is shaping our future. Let’s help shape AI." (`og.png`) and the title "Students are writing
  a letter about AI. Add your voice." The password page carries the same preview tags (`PREVIEW` in
  `functions/_middleware.js`): change them together with index.html's, and bump `?v=` on the image when it changes.

- 2026-11-28 David: Discord moderation, all set by `discord/setup.mjs`: medium verification (account at least
  5 minutes old), image filter for everyone, only admins can ping @everyone, slowmode (#general 5 s, #help 10 s,
  #introductions 60 s), #resources posted to by the core team only, and four AutoMod rules (other servers' invites,
  mass mentions, spam, slurs and sexual content) that block and report in #mod-log, core team exempt. Pinned guides
  in #resources and #team-chat come from `resourcesPin` and `teamPin` in messages.json.

## Pitfalls
- **The bot cannot pin.** Discord now keeps "Pin Messages" apart from Manage Messages, and the bot's role lacks it;
  only the server owner (April) can tick it on that role. The two guides were pinned by hand (2026-11-28); once
  pinned, the script finds and updates them. A new guide is posted unpinned until someone pins it.
- **Settings the script owns are put back on every run** (overwrites, slowmode, AutoMod rules, guide text). Change
  them in `discord/setup.mjs` or messages.json, not by hand.

- **Discord form limits.** Discord drops a form that breaks a limit and shows "didn't respond in time":
  input labels 45 characters, placeholders 100, form titles 45. `discord/test.mjs` checks the intro box.
- **Discord's three seconds.** The first answer must come within 3 s; slow work goes through `later()`.
  Each answer's time is in the function's logs.
- **The bot cannot list server members** (no privileged intent). Who is in the server comes from our database.
- **A hidden category hides itself from the bot too.** Every private category and channel must let the bot in by
  its user id, or it cannot add to it.
- **The bot test needs the server picture** (`our-futures-first-profile.png`, kept outside the repo). Without it,
  "server renamed and given a picture" fails; everything else should pass.
- **Supabase CLI:** version 2.62 cannot read `supabase/config.toml` (`[local_smtp]`); use 3.x.
- **Local admin page** uses `dev_admin_*` functions that exist only in `supabase/seed.sql`, never on live.
  `discord/test.mjs` expects the Discord tables empty, so seed data must not add rows there.
- **Never add, drop or reorder columns of `public.signups`.** `sweep_unconfirmed()` copies its rows by position;
  put new per-sign-up data in a side table keyed by the sign-up's id (2026-11-28, April's session).
- **Email delivery tracking** (2026-11-28, April's session): Resend posts every email event to the `resend-webhook`
  function (verify JWT off), which hands the raw body and Svix headers to `mail_event()`. That checks the signature
  in SQL against the Vault secret `resend_webhook_secret`, refuses anything over 10 minutes old, and stores the event
  in `mail_events` (kept 120 days). The admin page's "Email delivery" section reads `admin_mail_report()`. Vault
  also holds `resend_api_key` (send only, used by the database) and `resend_read_key` (full access, used to read
  Resend's status and to set the webhook up). Never print a secret: move it from Resend's answer straight into Vault.
- **Junk folders are invisible.** No provider tells a sender an email went to Junk. The admin page's stand-in is
  the share of sign-ups confirmed, per university, after at least an hour. A slow arrival after "delivered" is the
  university's own scanning (Microsoft Defender at MIT), not us.
- **Page switch for Discord:** with the `discord` switch off, every element with class `dsc` is hidden
  (`body.nodiscord .dsc`). Give any new Discord link or button that class.
- **Admin emails live only in the database** (`admins`, `discord_team`), never in the repo.
- **Writing style:** say "university", not "school"; U.S. only; no middle dot (U+00B7) anywhere on the site or admin page.

## Open

- Should joining Discord need a confirmed sign-up on the site? Today any U.S. university email gets in, and
  people who have not signed are pointed to the site.
- Core team list (`discord_team`) has one address. Add the others so their codes give them the Core team role.
- If someone changes their organizer choice on the site after joining Discord, their role does not change.
  Fine for the preview; a re-sync can come later.
- Which page switches are on at launch, and when the gate and Cloudflare Access come off.
- The About page promises things not built yet (a public comment on your signature, signing without signing up
  first, an early-December email). Build them or soften the words.
