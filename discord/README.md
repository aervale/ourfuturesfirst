# Discord bot

The organizers' Discord server has one bot. A newcomer sees only `#start-here`, presses
**Find my campus**, types their university email, gets a 6-digit code by email, types it back,
and lands in a private channel with everyone else who confirmed an email from the same university.
The code works for an hour. University mail filters often put the email in Junk, so the bot says to look there.

If the code never arrives, **Didn't get a code?** lets them ask the organizers instead. The request is
posted in `#mod-log` with **Approve** and **Decline** buttons, pings the Core team, and shows the email
they typed. Approving places them without the email check, so approve only people you can vouch for.

| Piece | Where |
| --- | --- |
| The bot (answers buttons and forms) | `supabase/functions/discord/index.ts`, a Supabase Edge Function |
| What it says, and the channel and role names | `supabase/functions/discord/messages.json` |
| Codes, who is where, each university's channel | `supabase/migrations/20261128000000_discord.sql` |
| Server layout: roles, channels, the start message | `discord/setup.mjs` |
| Local end-to-end check with a stand-in Discord | `discord/test.mjs` |

## First-time setup

1. **Database.** Run `supabase/migrations/20261128000000_discord.sql` once in Supabase > SQL Editor.
   Codes are emailed through Resend with the `resend_api_key` already in Vault.
2. **Discord application.** At discord.com/developers/applications make an application called
   Our Futures First. Copy its **Application ID** and **Public Key** (General Information), and under
   **Bot** press Reset Token and copy the token.
3. **Secrets.** Create `supabase/functions/.env` (git ignores it):

   ```
   DISCORD_PUBLIC_KEY=...
   DISCORD_BOT_TOKEN=...
   ```

4. **Deploy.**

   ```sh
   supabase login
   supabase functions deploy discord --remote=pexnchjiphwyftvhykih --no-verify-jwt --use-api
   supabase secrets set --env-file supabase/functions/.env --remote=pexnchjiphwyftvhykih
   ```

5. **Point Discord at it.** In the application's General Information, set **Interactions Endpoint URL**
   to `https://pexnchjiphwyftvhykih.supabase.co/functions/v1/discord` and save. Discord checks it answers.
   (Done on 2026-11-27.)
6. **Add the bot to the server.** `node discord/setup.mjs invite <application id>` prints the link.
7. **Lay the server out.** `node --env-file=supabase/functions/.env discord/setup.mjs`.

## The Core team

The Core team role sees every campus channel and `#mod-log`, and is the only role that can approve
or decline requests. Two ways onto it:

- Someone already in the server: give them the role in Discord (right-click their name > Roles).
- Someone not in yet: add their university email to the list, and they get the role when they
  confirm that address with an emailed code. In Supabase > SQL Editor:

  ```sql
  insert into public.discord_team (email) values ('name@university.edu');
  ```

  Approval by hand never gives the Core team role.

## Limits

Discord allows 250 roles and 500 channels per server. Each university uses one of each, so the bot
stops making campus channels at about 240 universities and posts in `#mod-log` instead.

## Changing the wording

Edit `messages.json`, deploy the function again (step 4, second command), then refresh the message
in `#start-here`:

```sh
node --env-file=supabase/functions/.env discord/setup.mjs message
```

## Database changes

`supabase/migrations/20261128000000_discord.sql` is the whole of the bot's side of the database and
runs on a database that has none of it. The live database was brought up to it in steps on
2026-11-27; after changing a function there, run just that `create or replace function` in the SQL Editor.
