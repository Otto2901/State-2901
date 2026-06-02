import webpush from 'npm:web-push';
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY   = Deno.env.get('APP_SERVICE_KEY')!;
const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY')!;
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')!;

webpush.setVapidDetails(
  'https://otto2901.github.io/State-2901/',
  VAPID_PUBLIC,
  VAPID_PRIVATE
);

const db = createClient(SUPABASE_URL, SERVICE_KEY);

async function sendToPlayers(names: string[], title: string, body: string, tag: string) {
  const validNames = names.filter(Boolean);
  if (!validNames.length) return;

  const { data: subs } = await db
    .from('push_subscriptions')
    .select('subscription, player_name')
    .in('player_name', validNames);

  if (!subs?.length) return;

  const payload = JSON.stringify({ title, body, tag, url: '/State-2901/#castlewar' });

  await Promise.allSettled(
    subs.map(row => webpush.sendNotification(row.subscription, payload))
  );
}

Deno.serve(async (req) => {
  // Verify webhook secret
  const authHeader = req.headers.get('Authorization') || '';
  if (authHeader !== `Bearer ${WEBHOOK_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  const { type, record, old_record } = await req.json();
  const rally = record;

  if (!rally) return new Response('OK');

  const marchInfo = rally.march_seconds ? ` · ${rally.march_seconds}s march` : '';

  // Rally INSERT: new rally created — notify coordinator
  if (type === 'INSERT') {
    await sendToPlayers(
      [rally.coordinator_name],
      '🏰 OPEN YOUR RALLY NOW',
      `Command received${marchInfo}. Open your rally immediately!`,
      'castle-rally-new'
    );
    // If rallier already assigned at insert, notify them too
    if (rally.rallier_name) {
      await sendToPlayers(
        [rally.rallier_name],
        `⚔️ MARCH NOW — ${rally.coordinator_name}`,
        `Rally is open${marchInfo}. Prepare your march!`,
        'castle-rally-ready'
      );
    }
  }

  // Rally UPDATE: rallier assigned or status changed to 'commanded'
  if (type === 'UPDATE') {
    const oldRallier = old_record?.rallier_name;
    const newRallier = rally.rallier_name;

    // Rallier was just assigned (wasn't set before)
    if (newRallier && newRallier !== oldRallier) {
      await sendToPlayers(
        [newRallier],
        '⚔️ Castle War — Rally Ready',
        `${rally.coordinator_name} opened a rally. Prepare your march!`,
        'castle-rally-ready'
      );
    }

    // Status changed to commanded — notify coordinator to open rally
    if (rally.status === 'commanded' && old_record?.status !== 'commanded') {
      await sendToPlayers(
        [rally.coordinator_name],
        '🔴 OPEN RALLY NOW',
        `Command from ${rally.commanded_by}${marchInfo}. Open immediately!`,
        'castle-rally-command'
      );
    }
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
