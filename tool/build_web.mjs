import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const project = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(project, 'build/web');
const args = process.argv.slice(2);
if (args.some((arg) => arg.startsWith('-o') || arg.startsWith('--output'))) {
  throw new Error('The offline packager requires the default build/web output.');
}
const build = spawnSync('flutter', [
  'build', 'web', ...args, '--release', '--no-web-resources-cdn',
], { cwd: project, stdio: 'inherit' });
if (build.error) throw build.error;
if (build.status !== 0) process.exit(build.status ?? 1);

// Flutter's legacy worker must not compete for the same service-worker scope.
await rm(resolve(output, 'flutter_service_worker.js'), { force: true });
const bootstrapPath = resolve(output, 'flutter_bootstrap.js');
const bootstrap = await readFile(bootstrapPath, 'utf8');
if (!bootstrap.includes('const offlineEnabled = false;')) {
  throw new Error('The expected custom Flutter bootstrap is missing.');
}
await writeFile(bootstrapPath, bootstrap.replace(
  'const offlineEnabled = false;', 'const offlineEnabled = true;',
));

async function listFiles(directory) {
  const paths = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) paths.push(...await listFiles(path));
    else paths.push(relative(output, path).replaceAll('\\', '/'));
  }
  return paths;
}

const resources = (await listFiles(output))
  .filter((path) => path !== 'offline_worker.js' && !path.endsWith('.map'))
  .sort();
const template = await readFile(resolve(project, 'web/offline_worker.js'), 'utf8');
const hash = createHash('sha256').update(template);
for (const path of resources) {
  hash.update(path).update(await readFile(resolve(output, path)));
}
const version = hash.digest('hex');
await writeFile(resolve(output, 'offline_worker.js'), template
  .replace('__BUILD_VERSION__', version)
  .replace('const RESOURCES = [];', `const RESOURCES = ${JSON.stringify(resources)};`));
console.log(`Offline bundle ready: ${resources.length} files, version ${version.slice(0, 12)}`);
