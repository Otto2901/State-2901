const CACHE = 'state2901-v13';

const CORE = [
  '/State-2901/',
  '/State-2901/index.html',
  '/State-2901/manifest.json',
  '/State-2901/icons/icon-192.png',
  '/State-2901/icons/icon-512.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Cinzel:wght@600;700;900&display=swap'
];

// Install — precache the shell + the third-party assets the app needs to boot
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(c =>
      // don't let one flaky CDN request fail the whole install
      Promise.allSettled(CORE.map(u => c.add(u)))
    )
  );
});

// Activate — clean old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch — network first, fall back to cache; keep the cache fresh on every hit.
// Supabase REST/Realtime calls are skipped so stale API data never gets served.
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.hostname.endsWith('supabase.co')) return;
  e.respondWith(
    fetch(e.request).then(res => {
      if (res && res.ok && (url.origin === location.origin || url.hostname.includes('jsdelivr') || url.hostname.includes('gstatic') || url.hostname.includes('googleapis'))) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
      }
      return res;
    }).catch(() => caches.match(e.request))
  );
});

// Push notification received
self.addEventListener('push', e => {
  if (!e.data) return;
  let data;
  try { data = e.data.json(); } catch { data = { title: 'State 2901', body: e.data.text() }; }

  const title = data.title || 'State 2901';
  const options = {
    body:    data.body  || '',
    icon:    '/State-2901/icons/icon-192.png',
    badge:   '/State-2901/icons/icon-192.png',
    tag:     data.tag   || 'state2901',
    data:    { url: data.url || '/State-2901/' },
    vibrate: [200, 100, 200],
    requireInteraction: data.persist || false
  };

  e.waitUntil(self.registration.showNotification(title, options));
});

// Notification click — open/focus the app
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data?.url || '/State-2901/';
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      const existing = list.find(c => c.url.includes('State-2901'));
      if (existing) return existing.focus();
      return clients.openWindow(url);
    })
  );
});
