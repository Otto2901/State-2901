const CACHE = 'state2901-v3';

// Install — cache core files
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll([
      '/State-2901/',
      '/State-2901/index.html',
      '/State-2901/manifest.json'
    ]))
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

// Fetch — network first, cache fallback
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
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
