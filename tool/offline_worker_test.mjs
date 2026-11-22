import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../web/offline_worker.js', import.meta.url), 'utf8');
const scope = 'https://example.test/tasks/';
const prefix = `local-tasks:${scope}:`;

function loadWorker(caches, fetch = () => { throw new Error('Unexpected network request'); }) {
  const handlers = {};
  const self = {
    registration: { scope },
    location: { origin: 'https://example.test' },
    clients: { claim: async () => {} },
    addEventListener: (name, handler) => { handlers[name] = handler; },
  };
  runInNewContext(source, { self, caches, fetch, URL, Request });
  return handlers;
}

test('A failed precache deletes the incomplete cache and rejects installation', async () => {
  const deleted = [];
  const handlers = loadWorker({
    open: async () => ({ addAll: async () => { throw new Error('Storage full'); } }),
    delete: async (name) => deleted.push(name),
  });
  let installation;
  handlers.install({ waitUntil: (promise) => { installation = promise; } });
  await assert.rejects(installation, /Storage full/);
  assert.deepEqual(deleted, [prefix + '__BUILD_VERSION__']);
});

test('Activation removes only previous caches from this application scope', async () => {
  const current = prefix + '__BUILD_VERSION__';
  const deleted = [];
  const handlers = loadWorker({
    keys: async () => [current, prefix + 'old', 'another-app', 'local-tasks:https://example.test/other/:old'],
    delete: async (name) => deleted.push(name),
  });
  let activation;
  handlers.activate({ waitUntil: (promise) => { activation = promise; } });
  await activation;
  assert.deepEqual(deleted, [prefix + 'old']);
});

test('Navigation and static resources use the scoped cache without fetching', async () => {
  const requested = [];
  const handlers = loadWorker({
    open: async () => ({ match: async (path) => {
      requested.push(path);
      return 'cached';
    } }),
  });
  for (const [url, mode] of [
    [scope, 'navigate'],
    [scope + 'sqlite3.wasm?version=1', 'cors'],
  ]) {
    let response;
    handlers.fetch({
      request: { url, method: 'GET', mode },
      respondWith: (promise) => { response = promise; },
    });
    assert.equal(await response, 'cached');
  }
  assert.deepEqual(requested, [scope + 'index.html', scope + 'sqlite3.wasm']);
});

test('The worker does not intercept writes, external origins or other scopes', () => {
  const handlers = loadWorker({});
  for (const [method, url] of [
    ['POST', scope],
    ['GET', 'https://other.test/tasks/sqlite3.wasm'],
    ['GET', 'https://example.test/other/sqlite3.wasm'],
  ]) {
    handlers.fetch({
      request: { method, url },
      respondWith: () => assert.fail('The request should not be intercepted'),
    });
  }
});
