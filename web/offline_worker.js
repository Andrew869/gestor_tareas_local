'use strict';

// These values are filled from the complete release bundle, not a hand-kept list.
const BUILD_VERSION = '__BUILD_VERSION__';
const RESOURCES = [];
const CACHE_PREFIX = `local-tasks:${self.registration.scope}:`;
const CACHE_NAME = CACHE_PREFIX + BUILD_VERSION;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    try {
      await cache.addAll(RESOURCES.map((path) => new Request(
        new URL(path, self.registration.scope), { cache: 'reload' },
      )));
    } catch (error) {
      await caches.delete(CACHE_NAME);
      throw error;
    }
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME) {
        await caches.delete(name);
      }
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (!url.href.startsWith(self.registration.scope)) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const path = event.request.mode === 'navigate'
      ? new URL('index.html', self.registration.scope).href
      : url.origin + url.pathname;
    return (await cache.match(path)) ?? fetch(event.request);
  })());
});
