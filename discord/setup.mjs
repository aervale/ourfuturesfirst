// Sets up the Our Futures First Discord server for the bot: name and picture, roles, channels,
// who can see what, and the "Find my campus" message in #start-here. Safe to run again: it finds
// what already exists by name and only adds or corrects.
//
//   node --env-file=supabase/functions/.env discord/setup.mjs            set the server up
//   node --env-file=supabase/functions/.env discord/setup.mjs message    only refresh the #start-here message (after editing messages.json)
//   node --env-file=supabase/functions/.env discord/setup.mjs avatar     only give the bot the project's picture
//   node --env-file=supabase/functions/.env discord/setup.mjs roles      only make or correct the roles
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
	MANAGE_MESSAGES: 1n << 13n, EMBED: 1n << 14n, HISTORY: 1n << 16n, MENTION_EVERYONE: 1n << 17n, MANAGE_ROLES: 1n << 28n,
	PUBLIC_THREADS: 1n << 35n, PRIVATE_THREADS: 1n << 36n, THREAD_SEND: 1n << 38n, PIN: 1n << 51n
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
// The bot's own picture: the same star as the server's (DISCORD_ICON for a different one).
if (process.argv[2] === 'avatar') {
	const path = process.env.DISCORD_ICON ?? here('../../our-futures-first-profile.png');
	const image = `data:image/png;base64,${readFileSync(path).toString('base64')}`;
	const bot = await discord('PATCH', '/users/@me', { avatar: image });
	console.log(`  ${bot.username} now has the picture from ${path}`);
	process.exit(0);
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
	system_channel_flags: 1 | 2 | 4 | 8, // no automatic "X joined" or tips messages
	verification_level: 2, // the Discord account must be at least 5 minutes old: stops throwaway accounts
	explicit_content_filter: 2 // Discord scans images from everyone
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
	} else {
		const change = {};
		for (const k of ['permissions', 'color', 'hoist']) if (k in wanted && found[k] !== wanted[k]) change[k] = wanted[k];
		if (Object.keys(change).length) found = await discord('PATCH', `/guilds/${guildId}/roles/${found.id}`, change);
	}
	return found;
}
// Newcomers see nothing but #start-here: @everyone loses "view channels", the roles carry it.
// Nobody but admins can ping @everyone or @here.
const everyone = roles.find(r => r.id === guildId);
if (BigInt(everyone.permissions) & (P.VIEW | P.MENTION_EVERYONE)) {
	await discord('PATCH', `/guilds/${guildId}/roles/${guildId}`, { permissions: String(BigInt(everyone.permissions) & ~(P.VIEW | P.MENTION_EVERYONE)) });
	note('@everyone can no longer see channels by default or ping everyone');
}
const team = await role(N.team, { permissions: String(P.VIEW), color: 0xd3993c, hoist: true, mentionable: true });
// Member: everyone who confirmed a university email; it is what lets them see the server.
// Organizer: campus organizers only, shown as their own group in the member list.
const member = await role(N.member, { permissions: String(P.VIEW) });
const organizer = await role(N.organizer, { permissions: String(P.VIEW), color: 0xa22c29, hoist: true });
// `roles`: only the roles above (and the owner's), nothing else; safe to run without touching any channel.
if (process.argv[2] === 'roles') {
	for (const r of [team, member, organizer]) await discord('PUT', `/guilds/${guildId}/members/${guild.owner_id}/roles/${r.id}`).catch(error => note(`Could not give the owner ${r.name}: ${error.message}`));
	console.log(`  Roles ready: ${[team, member, organizer].map(r => r.name).join(', ')}`);
	process.exit(0);
}

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
		for (const k of ['rate_limit_per_user', 'default_auto_archive_duration']) if (k in wanted && found[k] !== wanted[k]) change[k] = wanted[k];
		if (Object.keys(change).length) found = Object.assign(found, await discord('PATCH', `/channels/${found.id}`, change));
	}
	return found;
}

// #start-here: the one place everyone can see. Nobody but the bot writes in it.
const start = await channel(N.start, 0, {
	topic: 'Start here: find your campus.', position: 0,
	permission_overwrites: [{ id: guildId, type: 0, allow: String(P.VIEW | P.HISTORY), deny: String(TALK) }, botHere]
});

// Community: open to everyone who confirmed their university email (Member role). A new server's own "Text Channels" category is reused.
const stock = channels.find(c => c.type === 4 && c.name === 'Text Channels');
if (stock && !channels.some(c => c.type === 4 && c.name === N.community)) Object.assign(stock, await discord('PATCH', `/channels/${stock.id}`, { name: N.community }));
const community = await channel(N.community, 4);
await channel(N.announcements, 0, {
	parent_id: community.id, topic: 'News from the core team. Launch day details land here.',
	permission_overwrites: [deny(guildId, TALK), allow(team.id, TALK), botHere]
});
// Slowmode (seconds between one person's messages) keeps busy rooms readable; threads stay open a week, not a day.
const WEEK = 10080;
const introductions = await channel(N.introductions, 0, { parent_id: community.id, topic: 'Who you are, where you study, why you are here.', rate_limit_per_user: 60, default_auto_archive_duration: WEEK });
const general = await channel(N.general, 0, { parent_id: community.id, rate_limit_per_user: 5, default_auto_archive_duration: WEEK });
// #resources: the core team posts; everyone else reads and replies in threads.
const resources = await channel(N.resources, 0, {
	parent_id: community.id, topic: 'Flyers, talking points, the draft letter, how-tos.', default_auto_archive_duration: WEEK,
	permission_overwrites: [deny(guildId, P.SEND), allow(team.id, P.SEND), botHere]
});
const help = await channel(N.help, 0, { parent_id: community.id, topic: 'Stuck, or your campus is missing? Ask here.', rate_limit_per_user: 10, default_auto_archive_duration: WEEK });

// Campuses: one private channel per university, made by the bot as people arrive.
// The bot is let in by name: hiding a channel from @everyone hides it from the bot too, and it could then never add to it.
await channel(N.campuses, 4, { permission_overwrites: [deny(guildId, P.VIEW), botHere] });

// Team: the core team only.
const teamCategory = await channel(N.teamCategory, 4, { permission_overwrites: [deny(guildId, P.VIEW), allow(team.id, P.VIEW), botHere] });
// #team-chat: where the core team plans and decides, out of sight of everyone else.
const teamChat = await channel(N.teamChat, 0, {
	parent_id: teamCategory.id, topic: 'Core team only: plans, decisions, who is taking which university.',
	permission_overwrites: [deny(guildId, P.VIEW), allow(team.id, P.VIEW), botHere]
});
const log = await channel(N.log, 0, {
	parent_id: teamCategory.id, topic: 'Things the bot could not do by itself.',
	permission_overwrites: [deny(guildId, P.VIEW), allow(team.id, P.VIEW), botHere]
});

// ---------- The message in #start-here ----------
await startMessage(start.id);

// ---------- One link to hand out: it never expires and lands people in #start-here ----------
const invite = await discord('POST', `/channels/${start.id}/invites`, { max_age: 0, max_uses: 0, unique: false }).catch(error => (note(`No invite link made: ${error.message}`), null));

// ---------- Pinned guides: posted once, then kept up to date ----------
// Found by the bot's pin, or by its first line among the recent messages (a guide posted when pinning was not allowed).
async function pinned(channelId, content) {
	const name = channels.find(c => c.id === channelId)?.name;
	const head = content.split('\n')[0];
	const pins = await discord('GET', `/channels/${channelId}/pins`);
	let mine = pins.find(m => m.author?.id === me.id);
	const isPinned = !!mine;
	mine ??= (await discord('GET', `/channels/${channelId}/messages?limit=50`)).find(m => m.author?.id === me.id && !m.components?.length && m.content?.split('\n')[0] === head);
	if (mine && mine.content !== content) await discord('PATCH', `/channels/${channelId}/messages/${mine.id}`, { content });
	if (!mine) mine = await discord('POST', `/channels/${channelId}/messages`, { content, allowed_mentions: { parse: [] } });
	if (isPinned) return;
	await discord('PUT', `/channels/${channelId}/pins/${mine.id}`)
		.then(() => note(`Guide pinned in #${name}`))
		.catch(() => note(`Guide posted in #${name} but not pinned: give the bot's role "Pin Messages" (Server Settings > Roles), then run this again`));
}
const at = (c) => `<#${c.id}>`;
const words = { site: M.site, invite: invite?.code ? `https://discord.gg/${invite.code}` : M.site, general: at(general), help: at(help), log: at(log), introductions: at(introductions) };
const fill = (text) => text.replace(/\{(\w+)\}/g, (all, k) => words[k] ?? all);
await pinned(resources.id, fill(M.resourcesPin));
await pinned(teamChat.id, fill(M.teamPin));

// ---------- AutoMod: Discord itself blocks these before anyone sees them, and reports each block in #mod-log ----------
const existing = await discord('GET', `/guilds/${guildId}/auto-moderation/rules`);
const alert = { type: 2, metadata: { channel_id: log.id } };
const block = (custom_message) => ({ type: 1, metadata: custom_message ? { custom_message } : {} });
const rules = [
	{ name: 'Links to other servers', trigger_type: 1, actions: [block(M.inviteBlocked), alert],
	  trigger_metadata: { regex_patterns: ['(?i)(discord\\.gg|discord(app)?\\.com/invite)/[a-z0-9-]+'], allow_list: invite?.code ? [`discord.gg/${invite.code}`] : [] } },
	{ name: 'Mass mentions', trigger_type: 5, actions: [block(), alert], trigger_metadata: { mention_total_limit: 5, mention_raid_protection_enabled: true } },
	{ name: 'Spam', trigger_type: 3, actions: [block(), alert] },
	{ name: 'Slurs and sexual content', trigger_type: 4, actions: [block(), alert], trigger_metadata: { presets: [2, 3] } }
];
for (const rule of rules) {
	const body = { ...rule, event_type: 1, enabled: true, exempt_roles: [team.id] };
	const found = existing.find(r => r.name === rule.name);
	if (found) {
		const { trigger_type, ...change } = body; // a rule's trigger cannot change once made
		await discord('PATCH', `/guilds/${guildId}/auto-moderation/rules/${found.id}`, change);
	} else {
		await discord('POST', `/guilds/${guildId}/auto-moderation/rules`, body);
		note(`AutoMod rule made: ${rule.name}`);
	}
}

// ---------- The owner is on the core team ----------
for (const r of [team, member, organizer]) await discord('PUT', `/guilds/${guildId}/members/${guild.owner_id}/roles/${r.id}`).catch(error => note(`Could not give the owner ${r.name}: ${error.message}`));

console.log(`\nDone. Server id: ${guildId}`);
if (invite?.code) console.log(`Invite link for organizers: https://discord.gg/${invite.code}`);
console.log(`Put the bot's role above "${N.team}", "${N.member}" and "${N.organizer}" if it is not already (Server Settings > Roles): it can only hand out roles below its own.`);
