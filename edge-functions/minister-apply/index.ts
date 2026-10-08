import { createClient } from 'npm:@supabase/supabase-js@2';

// Public, no-login SvS Prep minister application endpoint. The
// minister_applications table has no anon policies at all, so this function
// (service-role key) is the only way a visitor can insert a row.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('APP_SERVICE_KEY')!;

const db = createClient(SUPABASE_URL, SERVICE_KEY);

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS }
  });
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

const POSITIONS = ['vp1', 'edu', 'vp2'];
const TROOP_TYPES = ['inf', 'lan', 'mar'];
const TIERS = ['T9', 'T10', 'T11'];
const FC_LEVELS = ['below', 'FC5', 'FC6', 'FC7', 'FC8', 'FC9', 'FC10'];
const PER_IP_LIMIT = 3;
const PER_IP_WINDOW_MS = 60 * 60 * 1000;
const GLOBAL_DAILY_LIMIT = 300;
const MAX_RESOURCE = 1e9;

function num(v: unknown, int: boolean): number | null {
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > MAX_RESOURCE) return null;
  if (int && !Number.isInteger(n)) return null;
  return n;
}

// true = allowed and counted, false = over the limit
async function checkRate(ipHash: string): Promise<boolean> {
  const { data: row } = await db
    .from('minister_submit_rate')
    .select('count, window_start')
    .eq('ip_hash', ipHash)
    .maybeSingle();

  const now = Date.now();
  const fresh = !row || now - new Date(row.window_start as string).getTime() > PER_IP_WINDOW_MS;
  if (!fresh && (row!.count as number) >= PER_IP_LIMIT) return false;

  await db.from('minister_submit_rate').upsert({
    ip_hash: ipHash,
    count: fresh ? 1 : (row!.count as number) + 1,
    window_start: fresh ? new Date(now).toISOString() : row!.window_start
  });
  return true;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'Invalid request.' }, 400); }

  // Honeypot: a hidden field real users never see. Pretend success for bots.
  if (body?.website) return json({ ok: true });

  const playerName = String(body?.player_name || '').trim();
  const playerId = String(body?.player_id || '').trim();
  if (playerName.length < 1 || playerName.length > 40) return json({ error: 'Player name must be 1-40 characters.' }, 400);
  if (!/^\d{1,20}$/.test(playerId)) return json({ error: 'Player ID must be digits only.' }, 400);

  const resources = {
    speed_construction: num(body?.speed_construction, false),
    speed_research: num(body?.speed_research, false),
    // Older cached clients don't send Training yet: missing means 0
    speed_training: body?.speed_training === undefined ? 0 : num(body?.speed_training, false),
    speed_general: num(body?.speed_general, false),
    fire_crystal: num(body?.fire_crystal, true),
    refined_fc: num(body?.refined_fc, true),
    fc_shards: num(body?.fc_shards, true)
  };
  for (const [k, v] of Object.entries(resources)) {
    if (v === null) return json({ error: `Invalid value for ${k}.` }, 400);
  }

  const rawPrefs = body?.prefs;
  if (!rawPrefs || typeof rawPrefs !== 'object' || Array.isArray(rawPrefs)) return json({ error: 'Invalid time preferences.' }, 400);
  for (const k of Object.keys(rawPrefs)) {
    if (!POSITIONS.includes(k)) return json({ error: 'Invalid time preferences.' }, 400);
  }
  const prefs: Record<string, number[]> = {};
  for (const p of POSITIONS) {
    const list = rawPrefs[p];
    if (list === undefined || list === null) continue;
    if (!Array.isArray(list) || list.length > 3) return json({ error: 'Up to 3 choices per position.' }, 400);
    if (list.length === 0) continue;
    if (!list.every((s: unknown) => Number.isInteger(s) && (s as number) >= 0 && (s as number) <= 47)) {
      return json({ error: 'Invalid time slot.' }, 400);
    }
    if (new Set(list).size !== list.length) return json({ error: 'Each choice must be a different time.' }, 400);
    prefs[p] = list as number[];
  }
  if (Object.keys(prefs).length === 0) return json({ error: 'Pick at least one position and time.' }, 400);

  // Troop levels: required, whitelisted, stored permanently in player_troop_reports
  const tr = body?.troops;
  const troopRow: Record<string, string> = {};
  for (const t of TROOP_TYPES) {
    const tier = tr?.[t]?.tier, fc = tr?.[t]?.fc;
    if (!TIERS.includes(tier) || !FC_LEVELS.includes(fc)) return json({ error: 'Fill in your troop levels.' }, 400);
    troopRow[t + '_tier'] = tier;
    troopRow[t + '_fc'] = fc;
  }

  // Alliance: required, must be in the Rotation alliance list or OTHER
  const alliance = String(body?.alliance || '').trim();
  if (alliance !== 'OTHER') {
    const { data: allies, error: allyErr } = await db.rpc('state_alliances');
    if (allyErr) return json({ error: 'Server error.' }, 500);
    if (!alliance || !(allies || []).some((a: any) => a.alliance === alliance)) return json({ error: 'Select your alliance.' }, 400);
  }

  const { data: cfg } = await db.from('minister_config').select('prep_start_date, status').eq('id', 1).maybeSingle();
  if (cfg?.status !== 'open' || !cfg?.prep_start_date) return json({ error: 'Applications are closed.' }, 403);

  const fwd = req.headers.get('x-forwarded-for') || req.headers.get('cf-connecting-ip') || 'unknown';
  const ipHash = await sha256Hex(fwd.split(',')[0].trim());
  if (!(await checkRate(ipHash))) return json({ error: 'Too many submissions. Try again later.' }, 429);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count: dayCount } = await db
    .from('minister_applications')
    .select('id', { count: 'exact', head: true })
    .eq('source', 'public')
    .gte('created_at', since);
  if ((dayCount || 0) >= GLOBAL_DAILY_LIMIT) return json({ error: 'Too many submissions today. Try again later.' }, 429);

  const { data: dup, error: dupErr } = await db
    .from('minister_applications')
    .select('id')
    .eq('player_id', playerId)
    .in('status', ['pending', 'approved'])
    .limit(1);
  if (dupErr) return json({ error: 'Server error.' }, 500);
  if (dup && dup.length) return json({ error: 'This Player ID has already applied. Contact an admin to change it.' }, 409);

  const { data: taken, error: takenErr } = await db.from('minister_assignments').select('position, slot');
  if (takenErr) return json({ error: 'Server error.' }, 500);
  const takenSet = new Set((taken || []).map((t: any) => t.position + ':' + t.slot));
  for (const [p, list] of Object.entries(prefs)) {
    if (list.some((s) => takenSet.has(p + ':' + s))) {
      return json({ error: 'One of your chosen times was just taken. Please refresh and choose again.', code: 'slot_taken' }, 409);
    }
  }

  const { data: appRow, error: insErr } = await db.from('minister_applications').insert({
    player_name: playerName,
    player_id: playerId,
    alliance,
    ...resources,
    prefs,
    source: 'public',
    status: 'pending'
  }).select('id').single();
  if (insErr) return json({ error: 'Server error.' }, 500);

  // The application matters more: a failed troop report is logged, not fatal
  const { error: trErr } = await db.from('player_troop_reports').insert({
    player_id: playerId,
    player_name: playerName,
    alliance,
    ...troopRow,
    source: 'public',
    svs_start_date: cfg.prep_start_date,
    application_id: appRow?.id ?? null
  });
  if (trErr) console.error('troop report insert failed', trErr.message);

  return json({ ok: true });
});
