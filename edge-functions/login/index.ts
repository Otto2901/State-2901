import { createClient } from 'npm:@supabase/supabase-js@2';

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

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'Invalid request.' }, 400); }

  const name = String(body?.name || '').trim();
  const pin = String(body?.pin || '');
  if (!name || !pin) return json({ error: 'Name and PIN required.' }, 400);

  const { data: player, error: findErr } = await db
    .from('players')
    .select('name, pin')
    .eq('name', name)
    .maybeSingle();

  if (findErr) return json({ error: 'Server error.' }, 500);
  if (!player) return json({ error: 'Player not found.' }, 404);

  const stored = (player.pin as string) || '';
  const storedIsHashed = /^[a-f0-9]{64}$/i.test(stored);
  const inputHash = await sha256Hex(pin);

  let ok: boolean;
  if (storedIsHashed) {
    ok = stored === inputHash;
  } else {
    ok = stored === pin;
    if (ok) {
      // Silently migrate legacy plaintext PIN to a hash, same as the old client-side behavior.
      await db.from('players').update({ pin: inputHash }).eq('name', name);
    }
  }

  if (!ok) return json({ error: 'Wrong PIN. Try again.' }, 401);

  const token = randomToken();
  const { error: insErr } = await db.from('sessions').insert({
    token,
    player_name: name,
    expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
  });
  if (insErr) return json({ error: 'Server error.' }, 500);

  return json({ token, name });
});
