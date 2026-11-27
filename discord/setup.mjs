// Sets up the Our Futures First Discord server for the bot: name and picture, roles, channels,
// who can see what, and the "Find my campus" message in #start-here. Safe to run again: it finds
// what already exists by name and only adds or corrects.
//
//   node --env-file=supabase/functions/.env discord/setup.mjs            set the server up
//   node --env-file=supabase/functions/.env discord/setup.mjs message    only refresh the #start-here message (after editing messages.json)
//   node discord/setup.mjs invite <application id>                       print the link that adds the bot
//
// Needs DISCORD_BOT_TOKEN (in supabase/functions/.env, which git ignores). Optional: DISCORD_GUILD_ID
// when the bot is in more than one server, DISCORD_ICON for a different picture.
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
const M = JSON.parse(readFileSync(here('../supabase/functions/discord/messages.json'), 'utf8'));
const N = M.names;
const API = process.env.DISCORD_API ?? 'https://discord.com/api/v10';
const TOKEN = process.env.DISCORD_BOT_TOKEN ?? '';

// Permission bits (discord.com/developers/docs/topics/permissions).
const P = {
	INVITE: 1n << 0n, MANAGE_CHANNELS: 1n << 4n, MANAGE_GUILD: 1n << 5n, ADD_REACTIONS: 1n << 6n, VIEW: 1n << 10n, SEND: 1n << 11n,
	MANAGE_MESSAGES: 1n << 13n, EMBED: 1n << 14n, HISTORY: 1n << 16n, MANAGE_ROLES: 1n << 28n,
	PUBLIC_THREADS: 1n << 35n, PRIVATE_THREADS: 1n << 36n, THREAD_SEND: 1n << 38n
};
// What the bot is allowed to do in the server. It can only grant or deny what it holds itself.
const BOT = Object.values(P).reduce((all, bit) => all | bit, 0n);
const TALK = P.SEND | P.ADD_REACTIONS | P.PUBLIC_THREADS | P.PRIVATE_THREADS | P.THREAD_SEND;
const BOT_HERE = String(P.VIEW | P.SEND | P.EMBED | P.HISTORY | P.MANAGE_MESSAGES);

if (process.argv[2] === 'invite') {
	const app = process.argv[3];
	if (!/^\d{15,22}$/.test(app ?? '')) throw new Error('Give the application id: node discord/setup.mjs invite 1234567890');
	console.log(`https://discord.com/oauth2/authorize?client_id=${app}&scope=bot+applications.commands&permissions=${BOT}`);
	process.exit(0);
}
if (!TOKEN) throw new Error('DISCORD_BOT_TOKEN is not set. Put it in supabase/functions/.env and run with --env-file.');

async function discord(method, path, body, tries = 4) {
	const response = await fetch(API + path, {
		method,
		headers: { authorization: `Bot ${TOKEN}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	if (response.status === 429 && tries > 1) {
		const wait = Number((await response.json().catch(() => ({}))).retry_after ?? 1);
		await new Promise(done => setTimeout(done, Math.min(30, wait) * 1000 + 200));
		return discord(method, path, body, tries - 1);
	}
	if (!response.ok) throw new Error(`Discord ${method} ${path}: ${response.status} ${(await response.text()).slice(0, 400)}`);
	return response.status === 204 ? null : response.json();
}
const said = [];
const note = (text) => (said.push(text), console.log('  ' + text));

// ---------- Which server ----------
const me = await discord('GET', '/users/@me');
const guilds = await discord('GET', '/users/@me/guilds');
const guildId = process.env.DISCORD_GUILD_ID ?? (guilds.length === 1 ? guilds[0].id : '');
if (!guildId) {
	throw new Error(guilds.length ? `The bot is in ${guilds.length} servers (${guilds.map(g => `${g.name}: ${g.id}`).join(', ')}). Set DISCORD_GUILD_ID.` : 'The bot is not in any server yet. Add it with the invite link first.');
}
const guild = await discord('GET', `/guilds/${guildId}`);

/**
 * The welcome message and its buttons: posted once, then edited in place. "Enter my code" is here as
 * well as on the bot's private reply, because that reply is gone once someone leaves the channel or
 * restarts Discord, and the code in their email works for an hour.
 */
async function startMessage(startId) {
	const message = {
		embeds: [{ title: M.start.title, description: M.start.body, color: 0xd3993c }],
		components: [{ type: 1, components: [
			{ type: 2, style: 1, custom_id: 'join', label: M.start.join },
			{ type: 2, style: 2, custom_id: 'code', label: M.enterCode },
			{ type: 2, style: 2, custom_id: 'guide', label: M.start.guide }
		] }]
	};
	const posted = (await discord('GET', `/channels/${startId}/messages?limit=50`)).find(m => m.author?.id === me.id && m.components?.length);
	if (posted) await discord('PATCH', `/channels/${startId}/messages/${posted.id}`, message);
	else await discord('POST', `/channels/${startId}/messages`, message);
	note(posted ? 'Start message updated' : 'Start message posted in #' + N.start);
}
if (process.argv[2] === 'message') {
	const found = (await discord('GET', `/guilds/${guildId}/channels`)).find(c => c.type === 0 && c.name === N.start);
	if (!found) throw new Error(`No #${N.start} channel yet. Run the full setup first.`);
	await startMessage(found.id);
	process.exit(0);
}
console.log(`Setting up "${guild.name}" (${guild.id}) as ${me.username}`);

// ---------- Name, picture, quiet defaults ----------
const iconPath = process.env.DISCORD_ICON ?? here('../../our-futures-first-profile.png');
const icon = existsSync(iconPath) ? `data:image/png;base64,${readFileSync(iconPath).toString('base64')}` : undefined;
await discord('PATCH', `/guilds/${guildId}`, {
	name: 'Our Futures First',
	...(icon ? { icon } : {}),
	default_message_notifications: 1, // only @mentions notify
	system_channel_flags: 1 | 2 | 4 | 8 // no automatic "X joined" or tips messages
});
note(icon ? 'Name and picture set' : `Name set. No picture: ${iconPath} not found`);

// ---------- Roles ----------
let roles = await discord('GET', `/guilds/${guildId}/roles`);
async function role(name, wanted) {
	let found = roles.find(r => r.name === name);
	if (!found) {
		found = await discord('POST', `/guilds/${guildId}/roles`, { name, ...wanted });
		roles.push(found);
		note(`Role made: ${name}`);
	} else if (wanted.permissions && found.permissions !== wanted.permissions) {
		found = await discord('PATCH', `/guilds/${guildId}/roles/${found.id}`, { permissions: wanted.permissions });
	}
	return found;
}
// Newcomers see nothing but #start-here: @everyone loses "view channels", the two roles carry it.
const everyone = roles.find(r => r.id === guildId);
if (BigInt(everyone.permissions) & P.VIEW) {
	await discord('PATCH', `/guilds/${guildId}/roles/${guildId}`, { permissions: String(BigInt(everyone.permissions) & ~P.VIEW) });
	note('@everyone can no longer see channels by default');
}
const team = await role(N.team, { permissions: String(P.VIEW), color: 0xd3993c, hoist: true, mentionable: true });
const organizer = await role(N.organizer, { permissions: String(P.VIEW) });

// ---------- Channels ----------
let channels = await discord('GET', `/guilds/${guildId}/channels`);
const deny = (id, bits) => ({ id, type: 0, deny: String(bits) });
const allow = (id, bits, type = 0) => ({ id, type, allow: String(bits) });
const botHere = { id: me.id, type: 1, allow: BOT_HERE };
async function channel(name, type, wanted = {}) {
	let found = channels.find(c => c.name === name && c.type === type);
	if (!found) {
		found = await discord('POST', `/guilds/${guildId}/channels`, { name, type, ...wanted });
		channels.push(found);
		note(`${type === 4 ? 'Category' : 'Channel'} made: ${name}`);
	} else {
		const change = {};
		if (wanted.parent_id && found.parent_id !== wanted.parent_id) change.parent_id = wanted.parent_id;
		if (wanted.permission_overwrites) change.permission_overwrites = wanted.permission_overwrites;
		if (wanted.topic && found.topic !== wanted.topic) change.topic = wanted.topic;
		if (Object.keys(change).length) found = Object.assign(found, await discord('PATCH', `/channels/${found.id}`, change));
	}
	return found;
}

// #start-here: the one place everyone can see. Nobody but the bot writes in it.
const start = await channel(N.start, 0, {
	topic: 'Start here: find your campus.', position: 0,
	permission_overwrites: [{ id: guildId, type: 0, allow: String(P.VIEW | P.HISTORY), deny: String(TALK) }, botHere]
});

// Community: open to every confirmed organizer. A new server's own "Text Channels" category is reused.
const stock = channels.find(c => c.type === 4 && c.name === 'Text Channels');
if (stock && !channels.some(c => c.type === 4 && c.name === N.community)) Object.assign(stock, await discord('PATCH', `/channels/${stock.id}`, { name: N.community }));
const community = await channel(N.community, 4);
await channel(N.announcements, 0, {
	parent_id: community.id, topic: 'News from the core team. Launch day details land here.',
	permission_overwrites: [deny(guildId, TALK), allow(team.id, TALK), botHere]
});
await channel(N.introductions, 0, { parent_id: community.id, topic: 'Who you are, where you study, why you are here.' });
await channel(N.general, 0, { parent_id: community.id });
await channel(N.resources, 0, { parent_id: community.id, topic: 'Flyers, talking points, the draft letter, how-tos.' });
await channel(N.help, 0, { parent_id: community.id, topic: 'Stuck, or your campus is missing? Ask here.' });

// Campuses: one private channel per university, made by the bot as people arrive.
// The bot is let in by name: hiding a channel from @everyone hides it from the bot too, and it could then never add to it.
await channel(N.campuses, 4, { permission_overwrites: [deny(guildId, P.VIEW), botHere] });

// Team: the core team only.
const teamCategory = await channel(N.teamCategory, 4, { permission_overwrites: [deny(guildId, P.VIEW), allow(team.id, P.VIEW), botHere] });
await channel(N.log, 0, {
	parent_id: teamCategory.id, topic: 'Things the bot could not do by itself.',
	permission_overwrites: [deny(guildId, P.VIEW), allow(team.id, P.VIEW), botHere]
});

// ---------- The message in #start-here ----------
await startMessage(start.id);

// ---------- One link to hand out: it never expires and lands people in #start-here ----------
const invite = await discord('POST', `/channels/${start.id}/invites`, { max_age: 0, max_uses: 0, unique: false }).catch(error => (note(`No invite link made: ${error.message}`), null));

// ---------- The owner is on the core team ----------
for (const r of [team, organizer]) await discord('PUT', `/guilds/${guildId}/members/${guild.owner_id}/roles/${r.id}`).catch(error => note(`Could not give the owner ${r.name}: ${error.message}`));

console.log(`\nDone. Server id: ${guildId}`);
if (invite?.code) console.log(`Invite link for organizers: https://discord.gg/${invite.code}`);
console.log(`Put the bot's role above "${N.team}" and "${N.organizer}" if it is not already (Server Settings > Roles): it can only hand out roles below its own.`);
