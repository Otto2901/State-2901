import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY    = Deno.env.get('APP_SERVICE_KEY')!;
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')!;

const db = createClient(SUPABASE_URL, SERVICE_KEY);

// Mirrors index.html's getSelectionWindowStatus()/getCurrentWeekStart():
// selections are open Wed 00:00 UTC through Fri 00:00 UTC.
function isSelectionWindowOpen(now: Date): boolean {
  const day = now.getUTCDay();
  const totalSecs = now.getUTCHours() * 3600 + now.getUTCMinutes() * 60 + now.getUTCSeconds();
  return day === 3 || day === 4 || (day === 5 && totalSecs < 1);
}

function currentWeekStartISO(now: Date): string {
  const day = now.getUTCDay();
  const diff = day === 0 ? -6 : 1 - day;
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + diff));
  return monday.toISOString();
}

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization') || '';

  let authorized = authHeader === `Bearer ${WEBHOOK_SECRET}`;
  if (!authorized) {
    // This app uses its own sessions table (x-session-token header), not Supabase Auth.
    const sessionToken = req.headers.get('x-session-token') || '';
    if (sessionToken) {
      const { data: session } = await db
        .from('sessions')
        .select('player_name, expires_at')
        .eq('token', sessionToken)
        .maybeSingle();
      authorized = !!session && new Date(session.expires_at as string) > new Date();
    }
  }
  if (!authorized) return new Response('Unauthorized', { status: 401 });

  const { data: state, error: stateErr } = await db
    .from('rotation_state')
    .select('*')
    .eq('id', 1)
    .maybeSingle();

  if (stateErr || !state) {
    return new Response(JSON.stringify({ ok: false, error: stateErr?.message || 'no rotation_state' }), { status: 500 });
  }

  const now = new Date();
  const windowOpen = state.force_open ? true : state.force_closed ? false : isSelectionWindowOpen(now);
  const currentWeek = currentWeekStartISO(now);
  const stateWeek = new Date(state.week_start).toISOString();

  // Only rotate once the window has closed for a week that hasn't been rotated yet.
  // Idempotent — safe to call from any client, any number of times.
  if (windowOpen || stateWeek.slice(0, 10) === currentWeek.slice(0, 10)) {
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const top4: string[] = state.top4_order || [];
  const bot5: string[] = state.bot5_order || [];
  const newTop4 = top4.length > 1 ? top4.slice(1).concat(top4[0]) : top4.slice();
  const newBot5 = bot5.length > 1 ? bot5.slice(1).concat(bot5[0]) : bot5.slice();

  const { data: updated, error: updErr } = await db
    .from('rotation_state')
    .update({
      top4_order: newTop4,
      bot5_order: newBot5,
      week_start: currentWeek,
      current_turn: 0,
      selections_done: false,
      updated_at: new Date().toISOString()
    })
    .eq('id', 1)
    .select()
    .single();

  if (updErr) {
    return new Response(JSON.stringify({ ok: false, error: updErr.message }), { status: 500 });
  }

  // Best-effort notify the new first alliance, mirroring rotNotifyEdge's behavior.
  const firstAlliance = newTop4[0];
  if (firstAlliance) {
    try {
      await db.functions.invoke('rotation-notify', {
        body: { alliance: firstAlliance },
        headers: { Authorization: `Bearer ${WEBHOOK_SECRET}` }
      });
    } catch (_e) {
      // notification failure shouldn't fail the reset itself
    }
  }

  return new Response(JSON.stringify({ ok: true, skipped: false, state: updated }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
