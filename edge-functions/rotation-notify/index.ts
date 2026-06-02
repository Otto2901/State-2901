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

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization') || '';
  if (authHeader !== `Bearer ${WEBHOOK_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  const { type, record, old_record } = await req.json();

  if (type !== 'UPDATE' || !record) return new Response('OK');

  // Only act when current_turn changes
  if (record.current_turn === old_record?.current_turn) return new Response('OK');

  // Find which alliance's turn it is
  const order = [...(record.top4_order || []), ...(record.bot5_order || [])];
  const currentAlliance = order[record.current_turn];
  if (!currentAlliance) return new Response('OK');

  // Find alliance reps (excluding TRANSFER role)
  const { data: reps } = await db
    .from('alliance_reps')
    .select('player_name')
    .eq('alliance', currentAlliance)
    .neq('alliance', 'TRANSFER');

  if (!reps?.length) return new Response(JSON.stringify({ ok: true, noReps: true }));

  const playerNames = reps.map((r: { player_name: string }) => r.player_name);

  // Get push subscriptions
  const { data: subs } = await db
    .from('push_subscriptions')
    .select('subscription, player_name')
    .in('player_name', playerNames);

  if (!subs?.length) return new Response(JSON.stringify({ ok: true, noSubs: true }));

  const payload = JSON.stringify({
    title: '🏯 Stronghold Rotation — Your Turn!',
    body:  `${currentAlliance} it's your turn to select your Stronghold & Fort.`,
    tag:   'rotation-turn',
    url:   '/State-2901/'
  });

  await Promise.allSettled(
    subs.map((row: { subscription: PushSubscription }) =>
      webpush.sendNotification(row.subscription, payload)
    )
  );

  return new Response(JSON.stringify({ ok: true, notified: subs.length }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
