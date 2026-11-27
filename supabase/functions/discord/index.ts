// The Our Futures First Discord bot. Discord calls this function whenever someone presses one of the
// bot's buttons or submits one of its forms (an "interactions endpoint"), so nothing has to stay running.
//
// What it does: a newcomer presses "Find my campus" in #start-here and types their university email.
// The database emails that address a 6-digit code (discord_start). When the code comes back
// (discord_finish) the bot gives them the Organizer role and their university's role, creating the
// university's private channel the first time someone from it arrives, and tells them what to do next.
//
// When the code never arrives ("Didn't get a code?") the newcomer can ask the organizers instead: the
// request goes to #mod-log with Approve and Decline buttons, and a core team member's Approve places
// them the same way (discord_request, discord_decide).
//
// Secrets (supabase secrets set): DISCORD_PUBLIC_KEY, DISCORD_BOT_TOKEN.
// The words the bot says, and the names of the channels and roles it looks for, are in messages.json.
// The server's channels and roles, and the message in #start-here, are made by discord/setup.mjs.
import M from './messages.json' with { type: 'json' };

const API = Deno.env.get('DISCORD_API') ?? 'https://discord.com/api/v10';
const TOKEN = Deno.env.get('DISCORD_BOT_TOKEN') ?? '';
const PUBLIC_KEY = Deno.env.get('DISCORD_PUBLIC_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Names the setup script gives things; the bot finds them by these.
const NAMES = M.names;
const VIEW = 1 << 10, SEND = 1 << 11, EMBED = 1 << 14, HISTORY = 1 << 16, MANAGE_MESSAGES = 1 << 13;
const EPHEMERAL = 64;
// Discord allows 250 roles and 500 channels in a server, and 50 channels in a category.
const MAX_ROLES = 245, MAX_CHANNELS = 490, PER_CATEGORY = 50;

type Json = Record<string, any>;

// ---------- Discord and database calls ----------
const hex = (text: string) => new Uint8Array((text.match(/.{2}/g) ?? []).map(byte => parseInt(byte, 16)));
let key: CryptoKey | undefined;
/** Discord signs every request; anything that does not carry its signature is refused. */
async function fromDiscord(request: Request, body: string): Promise<boolean> {
	const signature = request.headers.get('x-signature-ed25519');
	const time = request.headers.get('x-signature-timestamp');
	if (!signature || !time || !/^[0-9a-f]{64}$/i.test(PUBLIC_KEY) || !/^[0-9a-f]{128}$/i.test(signature)) return false;
	key ??= await crypto.subtle.importKey('raw', hex(PUBLIC_KEY), { name: 'Ed25519' }, false, ['verify']);
	return crypto.subtle.verify('Ed25519', key, hex(signature), new TextEncoder().encode(time + body));
}

async function discord(method: string, path: string, body?: unknown, tries = 3): Promise<any> {
	const response = await fetch(API + path, {
		method,
		headers: { authorization: `Bot ${TOKEN}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	if (response.status === 429 && tries > 1) {
		const wait = Math.min(5, Number((await response.json().catch(() => ({}))).retry_after ?? 1));
		await new Promise(done => setTimeout(done, wait * 1000));
		return discord(method, path, body, tries - 1);
	}
	if (!response.ok) throw new Error(`Discord ${method} ${path}: ${response.status} ${(await response.text()).slice(0, 300)}`);
	return response.status === 204 ? null : response.json();
}

async function rpc(name: string, args: Json): Promise<any> {
	const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
		method: 'POST',
		headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, 'content-type': 'application/json' },
		body: JSON.stringify(args)
	});
	if (!response.ok) throw new Error(`${name}: ${response.status} ${(await response.text()).slice(0, 300)}`);
	return response.status === 204 ? null : response.json();
}

// ---------- Words ----------
const fill = (text: string, values: Record<string, string | number>) => text.replace(/\{(\w+)\}/g, (all, name) => (name in values ? String(values[name]) : all));
const mention = (channels: Json[], name: string) => {
	const found = channels.find(channel => channel.type === 0 && channel.name === name);
	return found ? `<#${found.id}>` : `#${name}`;
};
function problem(code: string, values: Record<string, string | number> = {}) {
	const errors = M.errors as Record<string, string>;
	return fill(errors[code] ?? errors.other, values);
}

const reply = (data: Json) => Response.json({ type: 4, data: { flags: EPHEMERAL, allowed_mentions: { parse: [] }, ...data } });
const buttons = (...list: [id: string, label: string, style?: number][]) => [
	{ type: 1, components: list.map(([custom_id, label, style = 2]) => ({ type: 2, custom_id, label, style })) }
];
const modal = (custom_id: string, title: string, input: Json) =>
	Response.json({ type: 9, data: { custom_id, title, components: [{ type: 1, components: [{ type: 4, style: 1, required: true, ...input }] }] } });
const emailModal = () => modal('email', 'Find your campus', { custom_id: 'email', label: 'Your university email', placeholder: 'you@university.edu', min_length: 6, max_length: 160 });
const codeModal = () => modal('verify', 'Enter your code', { custom_id: 'code', label: 'The 6-digit code we emailed you', placeholder: '123456', min_length: 6, max_length: 12 });
const typed = (interaction: Json, id: string): string =>
	(interaction.data?.components ?? []).flatMap((row: Json) => row.components ?? []).find((input: Json) => input.custom_id === id)?.value ?? '';
const nameOf = (interaction: Json): string => {
	const user = interaction.member?.user ?? interaction.user ?? {};
	return interaction.member?.nick ?? user.global_name ?? user.username ?? '';
};
/** A direct message, when the person allows them; nothing is lost if they do not. */
const dm = (userId: string, content: string) =>
	discord('POST', '/users/@me/channels', { recipient_id: userId })
		.then(channel => discord('POST', `/channels/${channel.id}/messages`, { content, allowed_mentions: { parse: [] } }))
		.catch(() => null);

/**
 * Discord allows three seconds for the first answer, so slow work is answered at once and filled in after.
 * As a new private message by default; with `update`, by rewriting the message the button is on.
 * Work that returns null leaves things as they are.
 */
function later(interaction: Json, work: () => Promise<Json | null>, update = false): Response | Promise<Response> {
	const doing = work().catch(error => {
		console.error(error);
		return update ? null : ({ content: problem('other'), components: [] } as Json);
	});
	const runtime = (globalThis as Json).EdgeRuntime;
	if (!runtime?.waitUntil) return doing.then(message => (update ? Response.json(message ? { type: 7, data: message } : { type: 6 }) : reply(message ?? {})));
	runtime.waitUntil(
		doing
			.then(message => message && discord('PATCH', `/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`, { allowed_mentions: { parse: [] }, ...message }))
			.catch(error => console.error(error))
	);
	return Response.json(update ? { type: 6 } : { type: 5, data: { flags: EPHEMERAL } });
}

// ---------- Placing someone in their campus ----------
const slug = (name: string) => name.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 90) || 'campus';

/** The university's role and private channel, made the first time someone from it arrives. */
async function campus(guild: string, bot: string, dom: string, uni: string, roles: Json[], channels: Json[]): Promise<{ role: string; channel: string } | null> {
	let made = await rpc('discord_uni', { p_dom: dom, p_uni: uni });
	// Someone else from this university is being placed this very second: wait for their channel.
	for (let i = 0; !made.mine && !made.channel_id && i < 8; i++) {
		await new Promise(done => setTimeout(done, 1000));
		made = await rpc('discord_uni', { p_dom: dom, p_uni: uni });
	}
	if (made.role_id && made.channel_id) return { role: made.role_id, channel: made.channel_id };
	if (!made.mine) return null;
	if (roles.length >= MAX_ROLES || channels.length >= MAX_CHANNELS) return null;

	const role = made.role_id ? { id: made.role_id } : await discord('POST', `/guilds/${guild}/roles`, { name: uni.slice(0, 100), permissions: '0', mentionable: true });
	// The first "Campuses" category with room, or a new one ("Campuses 2", ...).
	const categories = channels.filter(c => c.type === 4 && c.name.toLowerCase().startsWith(NAMES.campuses.toLowerCase()));
	let parent = categories.find(category => channels.filter(c => c.parent_id === category.id).length < PER_CATEGORY);
	if (!parent) {
		parent = await discord('POST', `/guilds/${guild}/channels`, {
			name: categories.length ? `${NAMES.campuses} ${categories.length + 1}` : NAMES.campuses, type: 4,
			// the bot is let in by name, or it could not see the category it just made
			permission_overwrites: [{ id: guild, type: 0, deny: String(VIEW) }, { id: bot, type: 1, allow: String(VIEW) }]
		});
	}
	const team = roles.find(r => r.name === NAMES.team);
	const channel = await discord('POST', `/guilds/${guild}/channels`, {
		name: slug(uni), type: 0, parent_id: parent.id, topic: fill(M.campusTopic, { uni }).slice(0, 1000),
		permission_overwrites: [
			{ id: guild, type: 0, deny: String(VIEW) },
			{ id: role.id, type: 0, allow: String(VIEW) },
			...(team ? [{ id: team.id, type: 0, allow: String(VIEW) }] : []),
			{ id: bot, type: 1, allow: String(VIEW | SEND | EMBED | HISTORY | MANAGE_MESSAGES) }
		]
	});
	await rpc('discord_uni_save', { p_dom: dom, p_role_id: role.id, p_channel_id: channel.id });
	return { role: role.id, channel: channel.id };
}

/**
 * Roles, campus channel and greeting for someone the database has just recorded as a member
 * (discord_finish or discord_decide). Returns the words that tell them what to do next.
 */
async function settle(guild: string, bot: string, userId: string, result: Json, team = false): Promise<{ ok: boolean; text: string; channel?: string }> {
	const [roles, channels] = await Promise.all([discord('GET', `/guilds/${guild}/roles`), discord('GET', `/guilds/${guild}/channels`)]);
	const organizer = roles.find((r: Json) => r.name === NAMES.organizer);
	const give = (role: string) => discord('PUT', `/guilds/${guild}/members/${userId}/roles/${role}`);
	const take = (member: string, role: string) => discord('DELETE', `/guilds/${guild}/members/${member}/roles/${role}`).catch(() => null);
	if (organizer) await give(organizer.id);
	// Only ever after an emailed code: this address is on the core team list (discord_team).
	const teamRole = team ? roles.find((r: Json) => r.name === NAMES.team) : null;
	if (teamRole) await give(teamRole.id);

	const spot = await campus(guild, bot, result.dom, result.uni, roles, channels);
	const log = channels.find((c: Json) => c.type === 0 && c.name === NAMES.log);
	if (!spot) {
		if (log) await discord('POST', `/channels/${log.id}/messages`, { content: `<@${userId}> confirmed a **${result.uni}** email (${result.dom}) but no campus channel could be made. Add one by hand.`, allowed_mentions: { parse: [] } }).catch(() => null);
		return { ok: false, text: problem('full', { uni: result.uni }) };
	}
	await give(spot.role);

	// The email used to belong to another Discord account, or this account used to be at another university.
	if (result.replaced) {
		await take(result.replaced, spot.role);
		if (organizer) await take(result.replaced, organizer.id);
	}
	if (result.moved_from) {
		const before = await rpc('discord_uni', { p_dom: result.moved_from, p_uni: result.moved_from });
		if (before.role_id) await take(userId, before.role_id);
	}

	await discord('POST', `/channels/${spot.channel}/messages`, {
		content: fill(result.count > 1 ? M.campusJoined : M.campusFirst, { user: `<@${userId}>`, uni: result.uni, count: result.count }),
		allowed_mentions: { users: [userId] }
	}).catch(error => console.error(error));

	const values = {
		name: result.first_name ? `, ${result.first_name}` : '', uni: result.uni, campus: `<#${spot.channel}>`, site: M.site,
		people: result.count === 1 ? 'you are the first one here' : `${result.count} people`,
		introductions: mention(channels, NAMES.introductions), announcements: mention(channels, NAMES.announcements)
	};
	return { ok: true, text: fill(M.placed, values) + (result.signed ? '' : fill(M.notSigned, values)), channel: spot.channel };
}

/** Runs after the code form is submitted: check the code, hand out roles, say what to do next. */
async function place(interaction: Json): Promise<Json> {
	const user = interaction.member?.user ?? interaction.user;
	const result = await rpc('discord_finish', { p_discord_id: user.id, p_code: typed(interaction, 'code'), p_discord_name: nameOf(interaction) });
	if (result.error) {
		const again = result.error === 'wrong_code' ? buttons(['code', M.enterCode, 1], ['join', M.otherEmail], ['nocode', M.noCode]) : buttons(['join', M.start.join, 1]);
		return { content: problem(result.error), components: again };
	}
	const done = await settle(interaction.guild_id, interaction.application_id, user.id, result, !!result.team);
	return { content: done.text, components: [] };
}

// ---------- When the code never arrives ----------
const plain = (text: string) => String(text ?? '').replace(/[`*_~|>\\]/g, '').slice(0, 160);

/** "Ask the organizers": put the request in #mod-log for the core team, once. */
async function askTeam(interaction: Json): Promise<Json> {
	const guild: string = interaction.guild_id;
	const user = interaction.member?.user ?? interaction.user;
	const shown = nameOf(interaction);
	const asked = await rpc('discord_request', { p_discord_id: user.id, p_discord_name: shown });
	if (asked.error) return { content: problem(asked.error), components: asked.error === 'no_code' ? buttons(['join', M.start.join, 1]) : [] };
	if (asked.post) {
		const [roles, channels] = await Promise.all([discord('GET', `/guilds/${guild}/roles`), discord('GET', `/guilds/${guild}/channels`)]);
		const log = channels.find((c: Json) => c.type === 0 && c.name === NAMES.log);
		if (!log) throw new Error(`no #${NAMES.log} channel to put the request in`);
		const team = roles.find((r: Json) => r.name === NAMES.team);
		const text =
			fill(M.request, { team: team ? `<@&${team.id}>` : '', user: `<@${user.id}>`, name: plain(shown), email: plain(asked.email), uni: asked.uni }) +
			(asked.held_by ? fill(M.requestHeld, { other: `<@${asked.held_by}>`, uni: asked.uni }) : '');
		const posted = await discord('POST', `/channels/${log.id}/messages`, {
			content: text.slice(0, 2000),
			allowed_mentions: { roles: team ? [team.id] : [] }, // the core team is pinged; nobody else is
			components: buttons([`approve:${asked.id}`, M.approve, 3], [`decline:${asked.id}`, M.decline, 4])
		});
		await rpc('discord_request_posted', { p_request: asked.id, p_message_id: posted.id });
	}
	return { content: fill(asked.post ? M.requested : M.requestedAgain, { uni: asked.uni }), components: buttons(['code', M.enterCode, 1]) };
}

/** A core team member pressed Approve or Decline in #mod-log. Returns the rewritten request message. */
async function decide(interaction: Json, requestId: string, approve: boolean): Promise<Json | null> {
	const guild: string = interaction.guild_id;
	const bot: string = interaction.application_id;
	const by = interaction.member?.user ?? interaction.user;
	const whisper = (content: string) =>
		discord('POST', `/webhooks/${bot}/${interaction.token}`, { content, flags: EPHEMERAL, allowed_mentions: { parse: [] } }).catch(() => null);

	// #mod-log is only shown to the core team, but the button checks too: the role, or a server admin.
	const roles = await discord('GET', `/guilds/${guild}/roles`);
	const team = roles.find((r: Json) => r.name === NAMES.team);
	const admin = (BigInt(interaction.member?.permissions ?? 0) & 8n) !== 0n;
	if (!admin && !(team && (interaction.member?.roles ?? []).includes(team.id))) {
		await whisper(M.teamOnly);
		return null;
	}

	const was: string = interaction.message?.content ?? '';
	const stamp = (line: string) => ({ content: `${was}\n\n${line}`.slice(0, 2000), components: [] });
	const who = `<@${by.id}>`;
	const result = await rpc('discord_decide', { p_request: Number(requestId), p_by: by.id, p_approve: approve });
	if (result.error) return stamp(M.requestGone);
	if (!approve) {
		await dm(result.discord_id, M.declinedDm);
		return stamp(fill(M.declined, { by: who }));
	}
	if (result.already) return stamp(fill(M.approvedAlready, { by: who }));
	try {
		const done = await settle(guild, bot, result.discord_id, result);
		if (!done.ok) return stamp(fill(M.approvedStuck, { by: who }));
		await dm(result.discord_id, done.text);
		return stamp(fill(M.approved, { by: who, campus: `<#${done.channel}>` }));
	} catch (error) {
		console.error(error);
		return stamp(fill(M.approvedStuck, { by: who }));
	}
}

// ---------- The endpoint ----------
Deno.serve(async request => {
	if (request.method !== 'POST') return new Response('Our Futures First Discord bot', { status: 200 });
	const body = await request.text();
	if (!(await fromDiscord(request, body))) return new Response('Bad signature', { status: 401 });
	const interaction: Json = JSON.parse(body);

	if (interaction.type === 1) return Response.json({ type: 1 }); // Discord checking the address works
	const id: string = interaction.data?.custom_id ?? '';
	const user = interaction.member?.user ?? interaction.user;
	if (!interaction.guild_id || !user?.id) return reply({ content: 'Use this inside the Our Futures First server.' });

	try {
		if (interaction.type === 3) {
			// A button.
			if (id === 'join') return emailModal();
			if (id === 'code') return codeModal();
			if (id === 'guide') return reply({ content: fill(M.guide, { site: M.site, announcements: `#${NAMES.announcements}` }) });
			if (id === 'nocode') return reply({ content: M.noCodeHelp, components: buttons(['request', M.askTeam, 1], ['code', M.enterCode]) });
			if (id === 'request') return later(interaction, () => askTeam(interaction));
			const verdict = id.match(/^(approve|decline):(\d+)$/);
			if (verdict) return later(interaction, () => decide(interaction, verdict[2], verdict[1] === 'approve'), true);
		}
		if (interaction.type === 5 && id === 'email') {
			// The email form: send the code.
			const email = typed(interaction, 'email').trim();
			const sent = await rpc('discord_start', { p_discord_id: user.id, p_email: email });
			// Mail is off: the address is on record all the same, so the organizers can be asked straight away.
			if (sent.error === 'mail_off') return reply({ content: problem(sent.error), components: buttons(['request', M.askTeam, 1]) });
			if (sent.error) return reply({ content: problem(sent.error), components: buttons(['join', M.start.join, 1]) });
			return reply({ content: fill(M.codeSent, { email, uni: sent.uni }), components: buttons(['code', M.enterCode, 1], ['join', M.otherEmail], ['nocode', M.noCode]) });
		}
		// The code form: answer at once ("thinking"), then do the placing and fill the answer in.
		if (interaction.type === 5 && id === 'verify') return later(interaction, () => place(interaction));
	} catch (error) {
		console.error(error);
		return reply({ content: problem('other') });
	}
	return reply({ content: problem('other') });
});
