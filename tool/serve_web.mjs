import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const defaultRoot = fileURLToPath(new URL('../build/web/', import.meta.url));
const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

export function createWebServer({ root = defaultRoot, isolated = true, basePath = '/' } = {}) {
  root = resolve(root);
  if (!basePath.startsWith('/') || !basePath.endsWith('/')) {
    throw new Error('The base path must start and end with /.');
  }
  return createServer(async (request, response) => {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405).end();
      return;
    }
    try {
      const url = new URL(request.url, 'http://localhost');
      if (!url.pathname.startsWith(basePath)) {
        response.writeHead(404).end();
        return;
      }
      const path = decodeURIComponent(url.pathname.slice(basePath.length)) || 'index.html';
      const file = resolve(root, path);
      if (!file.startsWith(root + sep)) {
        response.writeHead(403).end();
        return;
      }
      const content = await readFile(file);
      response.setHeader('Content-Type', mimeTypes[extname(file)] ?? 'application/octet-stream');
      response.setHeader('Cache-Control', 'no-cache');
      if (isolated) {
        response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
        response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
      }
      response.writeHead(200).end(request.method === 'HEAD' ? undefined : content);
    } catch {
      response.writeHead(404).end();
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const port = Number(process.env.PORT ?? 8080);
  const basePath = process.env.BASE_PATH ?? '/';
  const server = createWebServer({ isolated: process.env.WEB_ISOLATION !== 'false', basePath });
  server.listen(port, '127.0.0.1', () => console.log(`Serving http://127.0.0.1:${port}${basePath}`));
}
