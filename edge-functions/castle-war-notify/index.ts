import webpush from 'npm:web-push';
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY    = Deno.env.get('APP_SERVICE_KEY')!;
const VAPID_PUBLIC   = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE  = Deno.env.get('VAPID_PRIVATE_KEY')!;
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')!;

webpush.setVapidDetails(
  'https://otto2901.github.io/State-2901/',
  VAPID_PUBLIC,
  VAPID_PRIVATE
);

const db = createClient(SUPABASE_URL, SERVICE_KEY);

function fmtUtc(iso: string): string {
  const d = new Date(iso);
  return [d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()]
    .map(n => String(n).padStart(2, '0')).join(':');
}

async function sendToPlayers(names: string[], title: string, body: string, tag: string) {
  const validNames = [...new Set(names.filter(Boolean))];
  if (!validNames.length) return;

  const { data: subs } = await db
    .from('push_subscriptions')
    .select('subscription, player_name')
    .in('player_name', validNames);

  if (!subs?.length) return;

  const payload = JSON.stringify({ title, body, tag, url: '/State-2901/#castlewar' });

  await Promise.allSettled(
    subs.map((row: any) => webpush.sendNotification(row.subscription, payload))
  );
}

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization') || '';

  // Accept webhook secret OR Supabase JWT from client
  let authorized = authHeader === `Bearer ${WEBHOOK_SECRET}`;
  if (!authorized) {
    const { data: { user }, error } = await db.auth.getUser(authHeader.replace('Bearer ', ''));
    authorized = !error && !!user;
  }
  if (!authorized) return new Response('Unauthorized', { status: 401 });

  const { type, record } = await req.json();
  const rally = record;
  if (!rally) return new Response('OK');

  // Rally opened (own or confirmed) — notify other alliances' coordinators & ralliers
  if (type === 'opened') {
    const openedAt = fmtUtc(rally.opened_at || new Date().toISOString());
    const opener   = rally.opened_by || rally.coordinator_name;

    const [{ data: coords }, { data: ralliers }] = await Promise.all([
      db.from('castle_coordinators').select('player_name').eq('war_id', rally.war_id).neq('alliance', rally.alliance),
      db.from('castle_ralliers').select('rallier_name').eq('war_id', rally.war_id).neq('alliance', rally.alliance)
    ]);

    const names = [
      ...((coords  || []) as any[]).map((c: any) => c.player_name),
      ...((ralliers || []) as any[]).map((r: any) => r.rallier_name)
    ];

    await sendToPlayers(
      names,
      `⚔️ ${opener} opened a rally — ${openedAt} UTC`,
      `${rally.alliance} · ${rally.march_seconds}s march · Open app for timer`,
      'castle-rally-opened'
    );
    return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } });
  }

  // Commanded rally — notify target alliance coordinators (and rallier if assigned)
  if (type === 'commanded') {
    const marchInfo = rally.march_seconds ? ` · ${rally.march_seconds}s march` : '';

    const { data: coords } = await db
      .from('castle_coordinators')
      .select('player_name')
      .eq('war_id', rally.war_id)
      .eq('alliance', rally.alliance);

    await sendToPlayers(
      ((coords || []) as any[]).map((c: any) => c.player_name),
      '🏰 OPEN YOUR RALLY NOW',
      `Command from ${rally.commanded_by}${marchInfo}. Open immediately!`,
      'castle-rally-new'
    );

    if (rally.rallier_name) {
      await sendToPlayers(
        [rally.rallier_name],
        `⚔️ Stand by — ${rally.commanded_by}`,
        `Rally command sent${marchInfo}. Open app for timer.`,
        'castle-rally-ready'
      );
    }
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
