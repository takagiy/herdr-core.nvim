import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFile, lstat, mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

const releases = 'https://releases.herdr.dev/core';
const versionPattern = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$/;

export async function installHc({
  directory,
  version = '',
  platform = process.platform,
  arch = process.arch,
  fetch = globalThis.fetch,
}) {
  if (version && !versionPattern.test(version)) throw new Error('Invalid hc version');
  const os = { linux: 'linux', win32: 'windows', darwin: 'macos' }[platform];
  const cpu = { x64: 'x86_64', arm64: 'aarch64' }[arch];
  if (!os || !cpu) throw new Error(`Unsupported platform: ${platform}-${arch}`);
  const target = `${os}-${cpu}`;
  await mkdir(directory, { mode: 0o700 });
  async function download(url) {
    const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${url}`);
    return Buffer.from(await response.arrayBuffer());
  }
  const manifestBytes = await download(version ? `${releases}/${version}/manifest.json` : `${releases}/latest.json`);
  await writeFile(join(directory, 'manifest.json'), manifestBytes);
  const manifest = JSON.parse(manifestBytes);
  if (typeof manifest?.version !== 'string' || !versionPattern.test(manifest.version)) throw new Error('Invalid manifest version');
  if (version && manifest.version !== version) throw new Error('Manifest version mismatch');
  const entry = manifest.targets?.[target];
  if (!entry) throw new Error(`No build for ${target}`);
  const { url, sha256 } = entry;
  if (typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/i.test(sha256)) throw new Error('Invalid SHA-256');
  if (typeof url !== 'string' || !url.startsWith(`${releases}/`)) throw new Error('Invalid release URL');
  await writeFile(join(directory, 'release.json'),
    JSON.stringify({ version: manifest.version, target, url, sha256 }, null, 2) + '\n');
  const archiveName = platform === 'win32' ? 'download.zip' : 'download.tar.gz';
  const bytes = await download(url);
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== sha256.toLowerCase()) throw new Error(`SHA-256 mismatch: expected ${sha256}, got ${actual}`);
  await writeFile(join(directory, archiveName), bytes);
  const bin = join(directory, 'bin');
  await mkdir(bin);
  const tar = process.platform === 'win32' ? join(process.env.SystemRoot, 'System32', 'tar.exe') : 'tar';
  const extracted = spawnSync(tar, ['-xf', archiveName, '-C', 'bin'], {
    cwd: directory, encoding: 'utf8', timeout: 60_000,
  });
  if (extracted.error) throw extracted.error;
  if (extracted.status !== 0) throw new Error(`tar failed: ${extracted.stderr}`);
  const executable = platform === 'win32' ? 'herdr-core.exe' : 'herdr-core';
  if (!(await lstat(join(bin, executable))).isFile()) throw new Error('Archive has no regular hc executable');
  await copyFile(join(bin, executable), join(bin, platform === 'win32' ? 'hc.exe' : 'hc'));
  return bin;
}

if (import.meta.main) {
  const [directory, version, ...extra] = process.argv.slice(2);
  if (!directory || extra.length) {
    console.error('Usage: node scripts/install-hc.mjs <new-private-directory> [version]');
    process.exitCode = 1;
  } else {
    try {
      console.log(await installHc({ directory: resolve(directory), version }));
    } catch (error) {
      console.error(`hc installer: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
