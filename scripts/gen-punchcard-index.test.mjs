import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  collectRows,
  compareRows,
  parseCardName,
  renderIndex,
} from './gen-punchcard-index.mjs';

const script = resolve(dirname(fileURLToPath(import.meta.url)), 'gen-punchcard-index.mjs');

function git(root, ...args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
}

function write(root, path, text) {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, text);
}

function card({ sessionClass = 'implementation', result = 'complete' } = {}) {
  return `\`\`\`yaml
session_class: "${sessionClass}"
last_commit_checked: "abcdef1234567890"
recommended_next_agent: "orchestrator"
\`\`\`

\`\`\`text
Punch-Out: BEGIN
Result: ${result}
Punch-Out: END
\`\`\`
`;
}

test('parses dashed, compact, and Z offsets as absolute instants', () => {
  const dashed = parseCardName('2026-08-11T11-04-02-04-00-local.md');
  const compact = parseCardName('2026-08-11T11-04-02-0400-compact.md');
  const utc = parseCardName('2026-08-11T13-05-00Z-utc.md');
  assert.equal(dashed.instant, compact.instant);
  assert.ok(dashed.instant > utc.instant, '11:04 EDT must sort after 13:05 UTC');
  assert.equal(dashed.stamp, '2026-08-11T11-04-02-04-00');
  assert.equal(compact.slug, 'compact');
  assert.equal(utc.slug, 'utc');
});

test('uses a total deterministic order with OUT before IN at the same instant', () => {
  const rows = [
    { ...parseCardName('2026-08-11T11-04-02-04-00-a.md'), kind: 'in', path: 'z' },
    { ...parseCardName('2026-08-11T15-04-02Z-a.md'), kind: 'out', path: 'b' },
    { ...parseCardName('2026-08-11T15-04-02+00-00-b.md'), kind: 'out', path: 'a' },
  ].sort(compareRows);
  assert.deepEqual(rows.map((row) => `${row.kind}:${row.path}`), ['out:a', 'out:b', 'in:z']);
});

test('renders byte-identically across repeated calls and timezone settings', () => {
  const rows = [{
    ...parseCardName('2026-08-11T11-04-02-04-00-example.md'),
    kind: 'out',
    path: 'docs/session-punch-cards/punch-outs/example.md',
    cls: 'implementation',
    range: 'abcdef1→1234567',
    result: 'complete',
    next: 'orchestrator',
  }];
  const originalTimezone = process.env.TZ;
  process.env.TZ = 'UTC';
  const utc = renderIndex(rows);
  process.env.TZ = 'America/New_York';
  const eastern = renderIndex(rows);
  if (originalTimezone === undefined) delete process.env.TZ;
  else process.env.TZ = originalTimezone;
  assert.equal(utc, eastern);
  assert.equal(renderIndex(rows), renderIndex(rows));
});

test('staged mode excludes untracked and unstaged punch-card content', () => {
  const root = mkdtempSync(join(tmpdir(), 'fernwx-punchcards-staged-'));
  git(root, 'init', '-q');
  git(root, 'config', 'user.name', 'Test');
  git(root, 'config', 'user.email', 'test@example.com');

  const stagedPath = 'docs/session-punch-cards/punch-outs/2026-08-11T11-04-02-04-00-staged.md';
  const untrackedPath = 'docs/session-punch-cards/punch-outs/2026-08-12T11-04-02-04-00-untracked.md';
  write(root, stagedPath, card({ sessionClass: 'staged-class' }));
  git(root, 'add', stagedPath);
  write(root, stagedPath, card({ sessionClass: 'unstaged-class' }));
  write(root, untrackedPath, card({ sessionClass: 'untracked-class' }));

  const rows = collectRows({ root, staged: true });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].slug, 'staged');
  assert.equal(rows[0].cls, 'staged-class');

  git(root, 'commit', '-q', '-m', 'initial-card');
  git(root, 'rm', '-q', '-f', stagedPath);
  assert.equal(collectRows({ root, staged: true }).length, 0, 'a staged deletion must leave the Index');
});

test('CLI check passes exact bytes and fails stale bytes', () => {
  const root = mkdtempSync(join(tmpdir(), 'fernwx-punchcards-check-'));
  const cardPath = 'docs/session-punch-cards/punch-ins/2026-08-11T11-04-02-04-00-check.md';
  write(root, cardPath, card());
  const generate = spawnSync(process.execPath, [script, '--repo', root], { encoding: 'utf8' });
  assert.equal(generate.status, 0, generate.stderr);
  const exact = readFileSync(join(root, 'docs/session-punch-cards/INDEX.md'), 'utf8');
  const passing = spawnSync(process.execPath, [script, '--repo', root, '--check'], { encoding: 'utf8' });
  assert.equal(passing.status, 0, passing.stderr);

  writeFileSync(join(root, 'docs/session-punch-cards/INDEX.md'), `${exact}\nmanual edit\n`);
  const stale = spawnSync(process.execPath, [script, '--repo', root, '--check'], { encoding: 'utf8' });
  assert.equal(stale.status, 1);
  assert.match(stale.stderr, /Punch-card Index is stale/);
});
