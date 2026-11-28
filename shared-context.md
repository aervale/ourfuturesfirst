# Shared context

What David, April and their Claude sessions need to know that the code does not say: decisions, how live is
changed, pitfalls, and open questions. Read it before starting work. Update it in the same commit as the change
that makes it true.

**This repository is public**, and until the password gate comes off every file is also served at the site's root.
Never put emails, tokens, passwords, people's names or anything private here.

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
- **Bot:** after changing `supabase/functions/discord/`, redeploy the `discord` function (verify JWT off: Discord
  signs its own requests) and say the new version number in the commit or here.
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

## Pitfalls

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
