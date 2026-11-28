// End-to-end check of the Discord bot on your own machine, with a stand-in for Discord.
// Needs the local database running (supabase start) with the discord migration applied.
//
//   node discord/test.mjs
//
// It starts a fake Discord API, runs discord/setup.mjs against it, serves the bot function with a
// test signing key, then plays a newcomer: button, email, code, placement. Nothing leaves this machine.
import { createServer } from 'node:http';
import { spawn, execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import { generateKeyPairSync, sign } from 'node:crypto';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const MOCK_PORT = 8791;
const FUNCTION = 'http://127.0.0.1:54421/functions/v1/discord';
const GUILD = '500000000000000001', BOT = '600000000000000001', OWNER = '700000000000000001';
const DB = 'supabase_db_uni_open_letter';
const sql = (query) => execFileSync('docker', ['exec', DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc', query], { encoding: 'utf8' }).trim();

let failed = 0;
function check(name, ok, detail = '') {
	console.log(`${ok ? '  ok  ' : '  FAIL'} ${name}${ok || !detail ? '' : `\n         ${detail}`}`);
	if (!ok) failed += 1;
}

// ---------- A stand-in for Discord ----------
let next = 1000;
const id = () => String(800000000000000000n + BigInt(next++));
const state = {
	guild: { id: GUILD, name: "April's server", owner_id: OWNER, icon: null },
	roles: [{ id: GUILD, name: '@everyone', permissions: String((1n << 10n) | (1n << 11n) | (1n << 16n)) }, { id: '600000000000000002', name: 'bot', permissions: '0' }],
	channels: [{ id: id(), name: 'Text Channels', type: 4 }, { id: id(), name: 'general', type: 0 }],
	messages: {}, memberRoles: {}, followups: [], whispers: [], dms: {}, calls: []
};
const mock = createServer((request, response) => {
	let raw = '';
	request.on('data', chunk => (raw += chunk));
	request.on('end', () => {
		const body = raw ? JSON.parse(raw) : undefined;
		const path = request.url.split('?')[0];
		state.calls.push(`${request.method} ${path}`);
		const send = (data, status = 200) => {
			response.writeHead(data === null ? 204 : status, { 'content-type': 'application/json' });
			response.end(data === null ? undefined : JSON.stringify(data));
		};
		let m;
		if (request.headers.authorization !== 'Bot test-token') return send({ message: '401: Unauthorized' }, 401);
		if (path === '/users/@me') return send({ id: BOT, username: 'Our Futures First' });
		if (path === '/users/@me/guilds') return send([{ id: GUILD, name: state.guild.name }]);
		if (path === `/guilds/${GUILD}`) {
			if (request.method === 'PATCH') Object.assign(state.guild, body, { icon: body.icon ? 'set' : state.guild.icon });
			return send(state.guild);
		}
		if (path === `/guilds/${GUILD}/roles`) {
			if (request.method === 'GET') return send(state.roles);
			const role = { id: id(), permissions: '0', ...body };
			state.roles.push(role);
			return send(role);
		}
		if ((m = path.match(/^\/guilds\/\d+\/roles\/(\d+)$/))) return send(Object.assign(state.roles.find(r => r.id === m[1]), body));
		if (path === `/guilds/${GUILD}/channels`) {
			// Like Discord, list only what the bot can see: a channel hidden from @everyone needs an entry letting the bot in.
			const sees = c => { const o = c.permission_overwrites ?? []; return !o.some(x => x.id === GUILD && (BigInt(x.deny ?? 0) & 1024n)) || o.some(x => x.id === BOT && (BigInt(x.allow ?? 0) & 1024n)); };
			if (request.method === 'GET') return send(state.channels.filter(sees));
			const channel = { id: id(), parent_id: null, ...body };
			state.channels.push(channel);
			return send(channel);
		}
		if ((m = path.match(/^\/channels\/(\d+)$/))) return send(Object.assign(state.channels.find(c => c.id === m[1]), body));
		if ((m = path.match(/^\/channels\/(\d+)\/messages$/))) {
			const list = (state.messages[m[1]] ??= []);
			if (request.method === 'GET') return send(list);
			const message = { id: id(), author: { id: BOT }, ...body };
			list.push(message);
			return send(message);
		}
		if (path.match(/^\/channels\/\d+\/invites$/)) return send({ code: 'testinvite' });
		if ((m = path.match(/^\/channels\/(\d+)\/messages\/(\d+)$/))) return send(Object.assign(state.messages[m[1]].find(x => x.id === m[2]), body));
		if ((m = path.match(/^\/guilds\/\d+\/members\/(\d+)\/roles\/(\d+)$/))) {
			const held = (state.memberRoles[m[1]] ??= new Set());
			if (request.method === 'PUT') held.add(m[2]);
			else held.delete(m[2]);
			return send(null);
		}
		if ((m = path.match(/^\/webhooks\/\d+\/([^/]+)\/messages\/@original$/))) {
			state.followups.push({ token: m[1], ...body });
			return send({ id: id() });
		}
		// A private follow-up to whoever pressed a button, and opening a direct message with someone.
		if ((m = path.match(/^\/webhooks\/\d+\/([^/]+)$/))) {
			state.whispers.push({ token: m[1], ...body });
			return send({ id: id() });
		}
		if (path === '/users/@me/channels') return send({ id: (state.dms[body.recipient_id] ??= id()) });
		send({ message: `mock has no ${request.method} ${path}` }, 404);
	});
});
await new Promise(done => mock.listen(MOCK_PORT, '0.0.0.0', done));

// ---------- Run the setup script against it, twice ----------
// Not execFileSync: the stand-in Discord lives in this process and has to answer while the script runs.
const setup = () => promisify(execFile)('node', [join(root, 'discord/setup.mjs')], { encoding: 'utf8', env: { ...process.env, DISCORD_API: `http://127.0.0.1:${MOCK_PORT}`, DISCORD_BOT_TOKEN: 'test-token' } });
console.log('Setup script');
await setup();
const names = (type) => state.channels.filter(c => c.type === type).map(c => c.name).sort().join(',');
check('server renamed and given a picture', state.guild.name === 'Our Futures First' && state.guild.icon === 'set');
check('roles made', ['Core team', 'Organizer'].every(n => state.roles.some(r => r.name === n)));
check('@everyone lost view-channels', (BigInt(state.roles[0].permissions) & (1n << 10n)) === 0n);
check('categories', names(4) === 'Campuses,Community,Team', names(4));
check('channels', names(0) === 'announcements,general,help,introductions,mod-log,resources,start-here,team-chat', names(0));
const start = state.channels.find(c => c.name === 'start-here');
check('start message with its three buttons', state.messages[start.id]?.length === 1 && state.messages[start.id][0].components[0].components.map(b => b.custom_id).join() === 'join,code,guide');
check('owner is on the core team', state.memberRoles[OWNER]?.size === 2);
const before = JSON.stringify([state.roles.length, state.channels.length, state.messages[start.id].length]);
await setup();
check('running it again adds nothing', before === JSON.stringify([state.roles.length, state.channels.length, state.messages[start.id].length]));

// ---------- Serve the bot with a test key ----------
const keys = generateKeyPairSync('ed25519');
const publicHex = keys.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('hex');
const dir = mkdtempSync(join(tmpdir(), 'off-discord-'));
writeFileSync(join(dir, 'env'), `DISCORD_API=http://host.docker.internal:${MOCK_PORT}\nDISCORD_BOT_TOKEN=test-token\nDISCORD_PUBLIC_KEY=${publicHex}\n`);
const serve = spawn('supabase', ['functions', 'serve', 'discord', '--no-verify-jwt', '--env-file', join(dir, 'env')], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
let serveLog = '';
serve.stdout.on('data', d => (serveLog += d));
serve.stderr.on('data', d => (serveLog += d));

async function interact(payload, { badSignature = false } = {}) {
	const body = JSON.stringify({ application_id: BOT, guild_id: GUILD, token: 'tok' + next++, ...payload });
	const time = String(Math.floor(Date.now() / 1000));
	const signature = sign(null, Buffer.from(time + (badSignature ? 'x' : '') + body), keys.privateKey).toString('hex');
	const response = await fetch(FUNCTION, { signal: AbortSignal.timeout(15000), method: 'POST', headers: { 'content-type': 'application/json', 'x-signature-ed25519': signature, 'x-signature-timestamp': time }, body });
	const text = await response.text();
	let json;
	try { json = JSON.parse(text); } catch { json = text; }
	return { status: response.status, json, token: JSON.parse(body).token };
}
const member = (userId, name) => ({ member: { user: { id: userId, username: name, global_name: name } } });
const button = (userId, custom_id) => interact({ type: 3, data: { custom_id }, ...member(userId, 'tester') });
// The email form also carries an introduction; tests give each person their own, so where it lands can be checked.
const introOf = userId => `Hi, I am tester ${userId} and I study things.`;
const form = (userId, custom_id, field, value, name = 'tester', intro = introOf(userId)) =>
	interact({ type: 5, data: { custom_id, components: [{ type: 1, components: [{ type: 4, custom_id: field, value }] },
		...(custom_id === 'email' ? [{ type: 1, components: [{ type: 4, custom_id: 'intro', value: intro }] }] : [])] }, ...member(userId, name) });
// The email form answers at once ("thinking") and fills the message in afterwards: this waits for that message.
// `first` is the immediate answer; `json.data` is the filled-in message, shaped like a direct reply's.
async function emailForm(userId, email, name, intro) {
	const r = await form(userId, 'email', 'email', email, name, intro);
	return { first: r.json, json: { data: await followup(r.token) } };
}
async function followup(token) {
	for (let i = 0; i < 60; i++) {
		const found = state.followups.find(f => f.token === token);
		if (found) return found;
		await new Promise(done => setTimeout(done, 250));
	}
	return null;
}

const A = '900000000000000001', B = '900000000000000002', C = '900000000000000003', D = '900000000000000004', E = '900000000000000005', TEAM = '900000000000000009';
const everyone = `'${A}','${B}','${C}','${D}','${E}'`;
const signed = sql("select email from public.signups where verified_at is not null and dom = 'mit.edu' order by created_at limit 1");
const clean = () => sql(`delete from public.discord_members where discord_id in (${everyone}); delete from public.discord_codes where discord_id in (${everyone}); delete from public.discord_asks where discord_id in (${everyone}); delete from public.discord_requests where discord_id in (${everyone}); delete from public.discord_team where email = '${signed}'; delete from public.discord_unis where dom = 'mit.edu';`);
const plant = (userId, email, code) => sql(`insert into public.discord_codes (discord_id, email, code_hash) values ('${userId}', '${email}', public.discord_code_hash('${userId}', '${code}')) on conflict (discord_id) do update set email = excluded.email, code_hash = excluded.code_hash, tries = 0, created_at = now()`);

try {
	clean();
	console.log('\nBot function');
	let ready = false;
	for (let i = 0; i < 90 && !ready; i++) {
		await new Promise(done => setTimeout(done, 1000));
		ready = await interact({ type: 1 }).then(r => r.status === 200 && r.json?.type === 1).catch(() => false);
	}
	check('answers Discord\'s ping', ready, serveLog.slice(-600));
	if (!ready) throw new Error('function did not start');

	check('refuses a request Discord did not sign', (await interact({ type: 1 }, { badSignature: true })).status === 401);
	const joinModal = await button(A, 'join');
	check('"Find my campus" opens the email form', joinModal.json?.type === 9 && joinModal.json.data.custom_id === 'email');
	check('the form asks for an introduction too', joinModal.json?.data?.components?.[1]?.components?.[0]?.custom_id === 'intro' && joinModal.json.data.components[1].components[0].style === 2, JSON.stringify(joinModal.json));
	const guide = await button(A, 'guide');
	check('"What do organizers do?" answers privately', guide.json?.type === 4 && guide.json.data.flags === 64 && /Bring people in/.test(guide.json.data.content));

	const gmail = await emailForm(A, 'someone@gmail.com');
	check('a non-university email is turned away', /could not match/.test(gmail.json?.data?.content ?? ''), JSON.stringify(gmail.json));
	const short = await emailForm(A, signed, 'tester', 'hi');
	check('a too-short introduction is turned away', /a little more/.test(short.json?.data?.content ?? ''), JSON.stringify(short.json));
	const start1 = await emailForm(A, signed);
	check('the email form is answered at once, then filled in', start1.first?.type === 5 && start1.first.data.flags === 64, JSON.stringify(start1.first));
	// No mail key on a local database, so the code is not sent; with one it says "We emailed a 6-digit code".
	check('a university email reaches the code step (or says mail is off locally)', /emailed a 6-digit code|cannot send codes/.test(start1.json?.data?.content ?? ''), JSON.stringify(start1.json));

	const again = await button(A, 'join');
	check('the form opens filled in the second time', again.json?.data?.components?.[0]?.components?.[0]?.value === signed && again.json.data.components[1].components[0].value === introOf(A), JSON.stringify(again.json));
	plant(A, signed, '123456');
	const wrong = await form(A, 'verify', 'code', '000000');
	check('code form is answered at once', wrong.json?.type === 5 && wrong.json.data.flags === 64, JSON.stringify(wrong.json));
	check('a wrong code is refused', /not right/.test((await followup(wrong.token))?.content ?? ''));

	const right = await form(A, 'verify', 'code', '123 456', 'Ada');
	const placed = await followup(right.token);
	const mitRole = state.roles.find(r => r.name === 'MIT');
	const mitChannel = state.channels.find(c => c.name === 'mit');
	const campuses = state.channels.find(c => c.type === 4 && c.name === 'Campuses');
	const organizer = state.roles.find(r => r.name === 'Organizer');
	check('MIT role and private #mit channel are made', !!mitRole && mitChannel?.parent_id === campuses.id, state.calls.slice(-12).join(' | '));
	check('#mit is hidden from everyone but MIT, the core team and the bot', (() => {
		const o = mitChannel?.permission_overwrites ?? [];
		return o.find(x => x.id === GUILD)?.deny === '1024' && o.find(x => x.id === mitRole?.id)?.allow === '1024' && o.some(x => x.id === BOT && x.type === 1) && o.length === 4;
	})(), JSON.stringify(mitChannel?.permission_overwrites));
	check('the newcomer gets Organizer and MIT', state.memberRoles[A]?.has(organizer.id) && state.memberRoles[A]?.has(mitRole?.id));
	check('they are told where to go', new RegExp(`<#${mitChannel?.id}>`).test(placed?.content ?? '') && /first one here/.test(placed.content) && !/could not find a confirmed sign-up/.test(placed.content), placed?.content);
	check('#mit greets them', /first one here from \*\*MIT\*\*/.test(state.messages[mitChannel?.id]?.[0]?.content ?? ''));
	check('#mit shows their introduction', (state.messages[mitChannel?.id]?.[0]?.content ?? '').includes(`> ${introOf(A)}`));
	const hello = state.channels.find(c => c.name === 'introductions');
	check('their introduction is posted in #introductions', (state.messages[hello.id]?.[0]?.content ?? '').includes(`<@${A}> from **MIT**`) && state.messages[hello.id][0].content.includes(introOf(A)), JSON.stringify(state.messages[hello.id]));
	check('their introduction becomes the description on the admin page', sql(`select b.bio from public.organizer_bios b join public.signups s on s.id = b.signup_id where s.email = '${signed}'`) === introOf(A));
	const linked = () => sql(`select m.discord_id from public.discord_members m join public.signups s on s.id = m.signup_id where s.email = '${signed}'`);
	check('their sign-up is linked to their Discord account', linked() === A);

	plant(B, 'not-signed-up@mit.edu', '654321');
	const second = await followup((await form(B, 'verify', 'code', '654321')).token);
	check('a second MIT person lands in the same channel', state.channels.filter(c => c.name === 'mit').length === 1 && state.memberRoles[B]?.has(mitRole.id) && /2 people/.test(second?.content ?? ''), second?.content);
	check('someone who has not signed is pointed at the site', /could not find a confirmed sign-up/.test(second?.content ?? ''));
	check('#mit announces the second arrival', /That makes 2 of you/.test(state.messages[mitChannel.id]?.[1]?.content ?? ''));

	plant(C, signed, '111111');
	await followup((await form(C, 'verify', 'code', '111111')).token);
	check('the same email from a new account moves the membership', state.memberRoles[C]?.has(mitRole.id) && !state.memberRoles[A]?.has(mitRole.id) && linked() === C);

	// ---------- "Didn't get a code?": ask the organizers, who approve or decline in #mod-log ----------
	const teamRole = state.roles.find(r => r.name === 'Core team');
	const log = state.channels.find(c => c.name === 'mod-log');
	const posts = () => state.messages[log.id] ?? [];
	const press = (userId, roles, post, which) =>
		interact({ type: 3, data: { custom_id: post.components[0].components[which].custom_id }, message: { id: post.id, content: post.content }, member: { user: { id: userId, username: 'presser' }, roles, permissions: '0' } });

	const noCode = await button(D, 'nocode');
	check('"Didn\'t get a code?" points at Junk and offers to ask the organizers', noCode.json?.type === 4 && /Junk/.test(noCode.json.data.content) && noCode.json.data.components[0].components.some(b => b.custom_id === 'request'), JSON.stringify(noCode.json));
	const tooSoon = await followup((await button(D, 'request')).token);
	check('asking before typing an email is turned away', /no code waiting/i.test(tooSoon?.content ?? '') && posts().length === 0, tooSoon?.content);

	const typedD = await emailForm(D, 'dana@mit.edu', 'Dana', 'Dana here, @everyone come say hi. I study physics.');
	check('the address is on record even when no mail can be sent', sql(`select email from public.discord_codes where discord_id = '${D}'`) === 'dana@mit.edu', JSON.stringify(typedD.json));
	const asked = await followup((await interact({ type: 3, data: { custom_id: 'request' }, ...member(D, 'Dana') })).token);
	check('the request reaches #mod-log with Approve and Decline', /^Asked/.test(asked?.content ?? '') && posts().length === 1 && /dana@mit\.edu/.test(posts()[0].content) && posts()[0].content.includes(`<@&${teamRole.id}>`)
		&& posts()[0].components[0].components.map(b => b.custom_id.split(':')[0]).join() === 'approve,decline', JSON.stringify(posts()));
	check('the request shows their introduction, with @everyone defused', /> Dana here, @\u200beveryone/.test(posts()[0].content), posts()[0].content);
	check('only the core team is pinged by it', JSON.stringify(posts()[0].allowed_mentions) === JSON.stringify({ roles: [teamRole.id] }));
	const askedAgain = await followup((await button(D, 'request')).token);
	check('asking twice does not post twice', posts().length === 1 && /already with the organizers/.test(askedAgain?.content ?? ''), askedAgain?.content);

	const sneaky = await press(E, [], posts()[0], 0);
	for (let i = 0; i < 40 && !state.whispers.length; i++) await new Promise(done => setTimeout(done, 250));
	check('someone outside the core team cannot approve', sneaky.json?.type === 6 && !state.memberRoles[D]?.has(mitRole.id) && /core team/i.test(state.whispers[0]?.content ?? '') && state.whispers[0]?.flags === 64, JSON.stringify(state.whispers));

	const approved = await followup((await press(TEAM, [teamRole.id], posts()[0], 0)).token);
	check('a core team member approves and the person is placed', /Approved\*\* by <@900000000000000009>/.test(approved?.content ?? '') && approved?.content.includes('dana@mit.edu') && approved.components.length === 0
		&& state.memberRoles[D]?.has(mitRole.id) && state.memberRoles[D]?.has(organizer.id), approved?.content);
	check('approval by hand never gives the Core team role', !state.memberRoles[D]?.has(teamRole.id));
	check('the approved person is told what to do next by direct message', /You're in/.test(state.messages[state.dms[D]]?.[0]?.content ?? ''), JSON.stringify(state.dms));
	const twice = await followup((await press(TEAM, [teamRole.id], posts()[0], 0)).token);
	check('a second press on the same request changes nothing', /already handled/.test(twice?.content ?? ''), twice?.content);

	await emailForm(E, 'eve@mit.edu', 'Eve');
	await followup((await button(E, 'request')).token);
	const declined = await followup((await press(TEAM, [teamRole.id], posts()[1], 1)).token);
	check('a declined request places nobody', /Declined\*\* by/.test(declined?.content ?? '') && !state.memberRoles[E]?.has(mitRole.id) && !state.memberRoles[E]?.has(organizer.id), declined?.content);
	const pushy = await followup((await button(E, 'request')).token);
	check('a declined person cannot ask again straight away', /could not confirm/.test(pushy?.content ?? '') && posts().length === 2, pushy?.content);

	// ---------- The core team list ----------
	sql(`insert into public.discord_team (email) values ('${signed}') on conflict do nothing`);
	plant(A, signed, '222222');
	await followup((await form(A, 'verify', 'code', '222222')).token);
	check('an address on the core team list gets the Core team role with its code', state.memberRoles[A]?.has(teamRole.id) && state.memberRoles[A]?.has(mitRole.id));

	check('new sign-ups on the site still work', sql('select public.sweep_unconfirmed()') === '');
	check('nothing was sent as a public reply', state.followups.every(f => f.allowed_mentions?.parse?.length === 0));
} catch (error) {
	check('test ran to the end', false, String(error));
} finally {
	if (failed) console.log('\n--- what the bot function logged ---\n' + serveLog.slice(-2500));
	clean();
	serve.kill('SIGINT');
	mock.close();
	rmSync(dir, { recursive: true, force: true });
}
console.log(failed ? `\n${failed} check(s) failed` : '\nAll checks passed');
process.exit(failed ? 1 : 0);
