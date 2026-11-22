import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { chromium } from 'playwright-core';
import { createWebServer } from './serve_web.mjs';

const executablePath = process.env.CHROME_EXECUTABLE ?? '/usr/bin/chromium';
const basePath = process.env.BASE_PATH ?? '/';

function launchBrowser(profile) {
  return chromium.launchPersistentContext(profile, {
    executablePath,
    headless: true,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader'],
    viewport: { width: 1000, height: 760 },
  });
}

function taskRow(page, title) {
  const escaped = title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return page.getByRole('group', {
    name: new RegExp(`^${escaped} ID: \\d+ · (Pendiente|Completada)$`),
  });
}

async function openApp(context, url) {
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder'));
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.getByRole('button', { name: 'Agregar tarea', exact: true }).waitFor();
  await page.waitForFunction(() => document.documentElement.dataset.offline === 'ready');
  return page;
}

async function addTask(page, title) {
  const input = page.getByRole('textbox', { name: 'Nueva tarea', exact: true });
  await input.click();
  await settleFrame(page);
  await input.fill(title);
  await settleFrame(page);
  await page.getByRole('button', { name: 'Agregar tarea', exact: true }).click();
  await taskRow(page, title.trim()).waitFor();
  await settleFrame(page);
}

// Flutter applies focus and controller changes on animation frames.
async function settleFrame(page) {
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

async function editFirstTask(page, title) {
  await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
  const input = page.getByRole('textbox', { name: 'Título', exact: true });
  await input.click();
  await settleFrame(page);
  await input.fill(title);
  await settleFrame(page);
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await taskRow(page, title.trim()).waitFor();
  await settleFrame(page);
}

async function deleteLastTask(page) {
  await page.getByRole('button', { name: 'Eliminar', exact: true }).last().click();
  await page.getByText('Eliminar tarea', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'Eliminar', exact: true }).last().click();
  await page.getByText('Eliminar tarea', { exact: true }).waitFor({ state: 'hidden' });
  await settleFrame(page);
}

for (const isolated of [true, false]) {
  test(`Chromium CRUD and cold offline restart (${isolated ? 'OPFS' : 'IndexedDB'})`, {
    timeout: 180000,
  }, async () => {
    const profile = await mkdtemp(join(tmpdir(), 'local-tasks-chromium-'));
    const server = createWebServer({ isolated, basePath });
    const networkRequests = [];
    server.on('request', (request) => networkRequests.push(request.url));
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const origin = `http://127.0.0.1:${server.address().port}`;
    const url = origin + basePath;
    const externalRequests = [];
    const errors = [];
    let context;
    async function launch(offline = false) {
      const browser = await launchBrowser(profile);
      browser.on('request', (request) => {
        if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== origin) {
          externalRequests.push(request.url());
        }
      });
      browser.on('page', (page) => page.on('pageerror', (error) => errors.push(String(error))));
      await browser.setOffline(offline);
      return browser;
    }

    try {
      context = await launch();
      let page = await openApp(context, url);
      await page.getByText('Todavía no hay tareas guardadas', { exact: true }).waitFor();
      assert.equal(await page.evaluate(() => window.crossOriginIsolated), isolated);
      const onlineRequestCount = networkRequests.length;

      await addTask(page, 'Online task');
      await addTask(page, 'Online deleted task');
      await editFirstTask(page, 'Edited online task');
      await page.getByRole('checkbox').first().click();
      await page.getByRole('group', { name: 'Edited online task ID: 1 · Completada', exact: true }).waitFor();
      await deleteLastTask(page);
      await taskRow(page, 'Edited online task').waitFor();
      await taskRow(page, 'Online deleted task').waitFor({ state: 'hidden' });
      assert.equal(networkRequests.length, onlineRequestCount, 'CRUD must not contact the HTTP server');

      const storage = await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const entries = await Array.fromAsync(root.keys());
        return {
          indexedDatabases: await indexedDB.databases(),
          opfsDatabases: entries.includes('drift_db')
            ? await Array.fromAsync((await root.getDirectoryHandle('drift_db')).keys())
            : [],
        };
      });
      if (isolated) {
        assert.ok(storage.opfsDatabases.includes('tasks'));
        assert.deepEqual(storage.indexedDatabases, []);
      } else {
        assert.ok(storage.indexedDatabases.some((database) => database.name === 'tasks'));
        assert.deepEqual(storage.opfsDatabases, []);
      }
      console.log(`Browser storage (${isolated ? 'isolated' : 'non-isolated'}): ${JSON.stringify(storage)}`);

      await context.close();
      context = undefined;
      await new Promise((resolve) => server.close(resolve));

      context = await launch(true);
      page = await openApp(context, url);
      await taskRow(page, 'Edited online task').waitFor();
      await page.getByRole('group', { name: 'Edited online task ID: 1 · Completada', exact: true }).waitFor();
      assert.equal(await taskRow(page, 'Online deleted task').count(), 0);

      await addTask(page, 'Offline deleted task');
      await editFirstTask(page, 'Edited offline task');
      await page.getByRole('checkbox').first().click();
      await page.getByRole('group', { name: 'Edited offline task ID: 1 · Pendiente', exact: true }).waitFor();
      await deleteLastTask(page);
      await taskRow(page, 'Edited offline task').waitFor();
      await taskRow(page, 'Offline deleted task').waitFor({ state: 'hidden' });

      await context.close();
      context = undefined;
      context = await launch(true);
      page = await openApp(context, url);
      await taskRow(page, 'Edited offline task').waitFor();
      await page.getByRole('group', { name: 'Edited offline task ID: 1 · Pendiente', exact: true }).waitFor();
      assert.equal(await page.getByRole('checkbox').count(), 1);
      assert.equal(await taskRow(page, 'Offline deleted task').count(), 0);
      assert.deepEqual(externalRequests, [], 'The app must not request external resources');
      assert.deepEqual(errors, [], 'The browser must not report uncaught errors');
    } catch (error) {
      const page = context?.pages().at(-1);
      if (page) {
        console.error(await page.locator('body').ariaSnapshot());
        console.error(await page.locator('input,textarea').evaluateAll((elements) =>
          elements.map((element) => element.outerHTML)));
      }
      throw error;
    } finally {
      await context?.close();
      if (server.listening) await new Promise((resolve) => server.close(resolve));
      await rm(profile, { recursive: true, force: true });
    }
  });
}

test('An updated bundle waits for old tabs and preserves SQLite after activation', {
  timeout: 180000,
}, async () => {
  const temporary = await mkdtemp(join(tmpdir(), 'local-tasks-update-'));
  const root = join(temporary, 'bundle');
  const profile = join(temporary, 'profile');
  await cp(fileURLToPath(new URL('../build/web/', import.meta.url)), root, { recursive: true });
  const server = createWebServer({ root, basePath });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}${basePath}`;
  let context;
  try {
    context = await launchBrowser(profile);
    let page = await openApp(context, url);
    await addTask(page, 'Task surviving an application update');
    const originalCaches = await page.evaluate(() => caches.keys());
    assert.equal(originalCaches.length, 1);

    const indexPath = join(root, 'index.html');
    await writeFile(indexPath, (await readFile(indexPath, 'utf8')).replace(
      '</head>', '<meta name="offline-test-version" content="B"></head>',
    ));
    const workerPath = join(root, 'offline_worker.js');
    await writeFile(workerPath, (await readFile(workerPath, 'utf8')).replace(
      /const BUILD_VERSION = '[^']+';/, "const BUILD_VERSION = 'update-test-b';",
    ));
    await page.evaluate(async () => {
      window.updateRegistration = await navigator.serviceWorker.getRegistration();
      await window.updateRegistration.update();
    });
    await page.waitForFunction(() => Boolean(window.updateRegistration.waiting));
    assert.equal(await page.locator('meta[name="offline-test-version"]').count(), 0);
    assert.ok((await page.evaluate(() => caches.keys())).includes(originalCaches[0]));

    let updatedWorker;
    for (const worker of context.serviceWorkers()) {
      if (await worker.evaluate(() => BUILD_VERSION) === 'update-test-b') {
        updatedWorker = worker;
      }
    }
    assert.ok(updatedWorker, 'The new worker must be waiting, not replace active tabs');
    await page.close();
    await updatedWorker.evaluate(async () => {
      const deadline = Date.now() + 30000;
      while (self.registration.waiting || self.registration.active?.state !== 'activated') {
        if (Date.now() > deadline) throw new Error('The new worker did not activate');
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
    });
    await context.close();
    context = undefined;
    context = await launchBrowser(profile);
    page = await openApp(context, url);
    assert.equal(await page.locator('meta[name="offline-test-version"]').getAttribute('content'), 'B');
    await taskRow(page, 'Task surviving an application update').waitFor();
    const updatedCaches = await page.evaluate(() => caches.keys());
    assert.equal(updatedCaches.length, 1);
    assert.ok(updatedCaches[0].endsWith('update-test-b'));

    await context.close();
    context = undefined;
    await new Promise((resolve) => server.close(resolve));
    context = await launchBrowser(profile);
    await context.setOffline(true);
    page = await openApp(context, url);
    assert.equal(await page.locator('meta[name="offline-test-version"]').getAttribute('content'), 'B');
    await taskRow(page, 'Task surviving an application update').waitFor();
  } finally {
    await context?.close();
    if (server.listening) await new Promise((resolve) => server.close(resolve));
    await rm(temporary, { recursive: true, force: true });
  }
});
