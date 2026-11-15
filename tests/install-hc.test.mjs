import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

const releases = 'https://releases.herdr.dev/core';

for (const version of ['', '0.1.20']) {
test(`Given ${version || 'latest'}, When installing, Then fetch one manifest and extract privately`, async (t) => {
  const { installHc } = await import('../scripts/install-hc.mjs');
  const root = await mkdtemp(join(tmpdir(), 'herdr-install-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const source = join(root, 'source');
  await mkdir(source);
  await writeFile(join(source, 'herdr-core'), 'test hc binary', { mode: 0o755 });
  const archive = join(root, 'fixture.tar.gz');
  const packed = spawnSync('tar', ['-czf', 'fixture.tar.gz', '-C', 'source', 'herdr-core'], { cwd: root });
  assert.equal(packed.status, 0, packed.stderr.toString());
  const bytes = await readFile(archive);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const selectedVersion = version || '0.1.21';
  const url = `${releases}/${selectedVersion}/herdr-core-linux-x86_64.tar.gz`;
  const manifest = { version: selectedVersion, targets: { 'linux-x86_64': { url, sha256 } } };
  const requests = [];
  const fetch = async (url) => {
    requests.push(url);
    return new Response(url.endsWith('.json') ? JSON.stringify(manifest) : bytes);
  };
  const normalHc = join(root, 'hc');
  await writeFile(normalHc, 'normal hc stays unchanged');
  const directory = join(root, 'private');

  await installHc({ directory, version, platform: 'linux', arch: 'x64', fetch });

  assert.deepEqual(requests, [version ? `${releases}/${version}/manifest.json` : releases + '/latest.json', url]);
  assert.equal(await readFile(join(directory, 'bin', 'hc'), 'utf8'), 'test hc binary');
  if (process.platform !== 'win32') assert.ok((await stat(join(directory, 'bin', 'hc'))).mode & 0o111);
  assert.equal(await readFile(normalHc, 'utf8'), 'normal hc stays unchanged');
  assert.deepEqual(JSON.parse(await readFile(join(directory, 'release.json'), 'utf8')),
    { version: selectedVersion, target: 'linux-x86_64', url, sha256 });
  await assert.rejects(installHc({ directory, fetch }), /EEXIST/);
});
}


test('Given a corrupted archive, When verifying, Then reject it before creating the extraction directory', async (t) => {
  const { installHc } = await import('../scripts/install-hc.mjs');
  const root = await mkdtemp(join(tmpdir(), 'herdr-install-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const directory = join(root, 'private');
  const manifest = { version: '0.1.21', targets: { 'linux-x86_64': {
    url: releases + '/0.1.21/herdr-core-linux-x86_64.tar.gz', sha256: '0'.repeat(64),
  } } };
  const fetch = async (url) => new Response(url.endsWith('.json') ? JSON.stringify(manifest) : 'corrupted');

  await assert.rejects(installHc({ directory, platform: 'linux', arch: 'x64', fetch }), /SHA-256 mismatch/);

  await assert.rejects(readFile(join(directory, 'bin', 'hc')), /ENOENT/);
  await assert.rejects(readFile(join(directory, 'download.tar.gz')), /ENOENT/);
});


test('Given invalid release metadata, When selecting hc, Then fail before downloading an archive', async (t) => {
  const { installHc } = await import('../scripts/install-hc.mjs');
  const root = await mkdtemp(join(tmpdir(), 'herdr-install-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const valid = { version: '0.1.21', targets: { 'linux-x86_64': {
    url: releases + '/0.1.21/herdr-core-linux-x86_64.tar.gz', sha256: '0'.repeat(64),
  } } };
  const cases = [
    { manifest: { ...valid, version: '../../bad' }, error: /Invalid manifest version/ },
    { manifest: valid, version: '0.1.20', error: /Manifest version mismatch/ },
    { manifest: { ...valid, targets: {} }, error: /No build for linux-x86_64/ },
    { manifest: { ...valid, targets: { 'linux-x86_64': { ...valid.targets['linux-x86_64'], sha256: 'bad' } } }, error: /Invalid SHA-256/ },
    { manifest: { ...valid, targets: { 'linux-x86_64': { ...valid.targets['linux-x86_64'], url: 'http://releases.herdr.dev/core/hc.tar.gz' } } }, error: /Invalid release URL/ },
    { manifest: { ...valid, targets: { 'linux-x86_64': { ...valid.targets['linux-x86_64'], url: 'https://example.org/hc.tar.gz' } } }, error: /Invalid release URL/ },
  ];
  for (const [index, { manifest, version, error }] of cases.entries()) {
    let requests = 0;
    const fetch = async () => {
      requests++;
      return new Response(JSON.stringify(manifest));
    };
    await assert.rejects(installHc({
      directory: join(root, String(index)), platform: 'linux', arch: 'x64', version, fetch,
    }), error);
    assert.equal(requests, 1);
  }
});

test('Given an unsafe version or unsupported platform, When starting, Then reject before network access', async (t) => {
  const { installHc } = await import('../scripts/install-hc.mjs');
  const root = await mkdtemp(join(tmpdir(), 'herdr-install-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const fetch = () => assert.fail('must not fetch');
  await assert.rejects(installHc({ directory: join(root, 'version'), version: '../latest', fetch }), /Invalid hc version/);
  await assert.rejects(installHc({ directory: join(root, 'platform'), platform: 'freebsd', fetch }), /Unsupported platform/);
});

test('Given a failed HTTP response, When fetching the manifest, Then report its URL and stop', async (t) => {
  const { installHc } = await import('../scripts/install-hc.mjs');
  const root = await mkdtemp(join(tmpdir(), 'herdr-install-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const fetch = async (_url, options) => {
    assert.ok(options.signal instanceof AbortSignal);
    return new Response('unavailable', { status: 503 });
  };
  await assert.rejects(installHc({ directory: join(root, 'private'), fetch }), /HTTP 503: https:\/\/releases.herdr.dev\/core\/latest.json/);
});
