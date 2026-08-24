#!/usr/bin/env node
// Deterministically render docs/session-punch-cards/INDEX.md.
//
// Default (backward compatible): read punch cards from the working tree and
// update INDEX.md in place.
//   node scripts/gen-punchcard-index.mjs
//
// Commit gate: render only stage-0 cards from Git's index to stdout. This keeps
// untracked, unstaged, and partially staged card content out of the commit.
//   node scripts/gen-punchcard-index.mjs --staged --stdout
//
// CI: compare the committed working-tree cards with the committed Index.
//   node scripts/gen-punchcard-index.mjs --check

import { execFileSync } from 'node:child_process';
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const defaultRoot = resolve(dirname(scriptPath), '..');
const INDEX_RELATIVE = 'docs/session-punch-cards/INDEX.md';
const CARD_DIRS = {
  in: 'docs/session-punch-cards/punch-ins',
  out: 'docs/session-punch-cards/punch-outs',
};

// Historical filenames use all three offset spellings below:
//   ...-04-00-slug.md, ...-0400-slug.md, and ...Z-slug.md.
const NAME_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})(Z|[+-]\d{2}-?\d{2})-(.+)\.md$/;

function byteCompare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

export function parseCardName(file) {
  const match = file.match(NAME_RE);
  if (!match) {
    return {
      stamp: file.replace(/\.md$/, ''),
      slug: '',
      instant: null,
      parsed: false,
    };
  }

  const [, year, month, day, hour, minute, second, rawOffset, slug] = match;
  let offset = rawOffset;
  if (rawOffset !== 'Z') {
    const offsetMatch = rawOffset.match(/^([+-])(\d{2})-?(\d{2})$/);
    offset = `${offsetMatch[1]}${offsetMatch[2]}:${offsetMatch[3]}`;
  }
  const iso = `${year}-${month}-${day}T${hour}:${minute}:${second}${offset}`;
  const instant = Date.parse(iso);

  return {
    stamp: `${year}-${month}-${day}T${hour}-${minute}-${second}${rawOffset}`,
    slug,
    instant: Number.isFinite(instant) ? instant : null,
    parsed: Number.isFinite(instant),
  };
}

function field(text, key) {
  const match = text.match(new RegExp(`^\\s*${key}:\\s*"?([^"\\n]+?)"?\\s*$`, 'm'));
  return match ? match[1].trim() : '';
}

function resultLabel(text) {
  const match = text.match(/^\s*Result:\s*(.+?)\s*$/m);
  return match ? match[1].trim() : '';
}

function short(sha) {
  if (!sha) return '';
  const match = sha.match(/[0-9a-f]{7,40}/i);
  return match ? match[0].slice(0, 7) : sha.replace(/\s+.*$/, '').slice(0, 18);
}

function rowFromCard({ kind, path, file, text }) {
  const parsed = parseCardName(file);
  const baseCommit = short(field(text, 'base_commit') || field(text, 'last_commit_checked'));
  const resultCommit = short(field(text, 'result_commit'));
  return {
    ...parsed,
    kind,
    path,
    cls: field(text, 'session_class') || '—',
    range: baseCommit || resultCommit ? `${baseCommit || '—'}→${resultCommit || '—'}` : '—',
    result: kind === 'out' ? resultLabel(text) || field(text, 'result') || '—' : '—',
    next: field(text, 'recommended_next_agent') || '—',
  };
}

export function compareRows(a, b) {
  if (a.instant !== null && b.instant !== null && a.instant !== b.instant) {
    return b.instant - a.instant;
  }
  if (a.instant !== null && b.instant === null) return -1;
  if (a.instant === null && b.instant !== null) return 1;
  if (a.kind !== b.kind) return a.kind === 'out' ? -1 : 1;
  const pathOrder = byteCompare(a.path, b.path);
  return pathOrder || byteCompare(b.stamp, a.stamp);
}

function collectFromDirectory(root, kind) {
  const relativeDir = CARD_DIRS[kind];
  const dir = join(root, relativeDir);
  let files = [];
  try {
    files = readdirSync(dir).filter((file) => file.endsWith('.md') && file !== 'INDEX.md');
  } catch {
    return [];
  }
  return files.map((file) => {
    const path = `${relativeDir}/${file}`;
    let text = '';
    try {
      text = readFileSync(join(root, path), 'utf8');
    } catch {
      // Preserve an unreadable tracked filename as a visible, schema-empty row.
    }
    return rowFromCard({ kind, path, file, text });
  });
}

function git(root, args, options = {}) {
  return execFileSync('git', ['-C', root, ...args], {
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
}

function collectFromGitIndex(root) {
  const pathspecs = Object.values(CARD_DIRS).map((dir) => `${dir}/*.md`);
  const unmerged = git(root, ['ls-files', '--unmerged', '-z', '--', ...pathspecs]);
  if (unmerged.length > 0) {
    throw new Error('punch-card index: resolve staged punch-card conflicts before committing');
  }

  const listed = git(root, ['ls-files', '--cached', '-z', '--', ...pathspecs]);
  const paths = listed
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .filter((path) => path.endsWith('.md') && !path.endsWith('/INDEX.md'));
  if (paths.length === 0) return [];

  const snapshot = mkdtempSync(join(tmpdir(), 'fernwx-punchcard-index-'));
  try {
    const prefix = `${snapshot}/`;
    git(root, ['checkout-index', '-z', '--stdin', `--prefix=${prefix}`], {
      input: Buffer.from(`${paths.join('\0')}\0`),
    });
    return paths.map((path) => {
      const relativeDir = dirname(path);
      const kind = relativeDir === CARD_DIRS.out ? 'out' : 'in';
      const file = path.slice(relativeDir.length + 1);
      return rowFromCard({
        kind,
        path,
        file,
        text: readFileSync(join(snapshot, path), 'utf8'),
      });
    });
  } finally {
    rmSync(snapshot, { recursive: true, force: true });
  }
}

export function collectRows({ root = defaultRoot, staged = false } = {}) {
  const rows = staged
    ? collectFromGitIndex(root)
    : [...collectFromDirectory(root, 'in'), ...collectFromDirectory(root, 'out')];
  return rows.sort(compareRows);
}

const escapeCell = (value) => String(value).replace(/\|/g, '\\|');

export function renderIndex(rows) {
  const ins = rows.filter((row) => row.kind === 'in').length;
  const outs = rows.filter((row) => row.kind === 'out').length;
  const header = `# Session Punch-Card Index

_Generated by \`scripts/gen-punchcard-index.mjs\`; the commit gate renders the staged punch-card tree and CI verifies the committed bytes — do not hand-edit._
_${rows.length} cards (${ins} punch-ins · ${outs} punch-outs), newest instant first. Displayed timestamps preserve each card's filename._

This is the latest-pointer for the handoff trail. The **newest punch-out** is the current
handoff record; find the matching punch-in above/below it by timestamp. Punch cards are the
durable *handoff* record; \`docs/STATE.md\` is the durable *current-state* record.

| Timestamp | Kind | Class | Base→Result | Result | Next agent | Card |
|---|---|---|---|---|---|---|
`;
  const body = rows
    .map(
      (row) =>
        `| ${row.stamp} | ${row.kind === 'in' ? 'IN' : 'OUT'} | ${escapeCell(row.cls)} | ${escapeCell(
          row.range,
        )} | ${escapeCell(row.result)} | ${escapeCell(row.next)} | ${escapeCell(row.slug)} |`,
    )
    .join('\n');
  return `${header}${body}\n`;
}

function usage() {
  return `Usage: node scripts/gen-punchcard-index.mjs [--repo PATH] [--staged --stdout | --check]

  (no flags)          Read working-tree cards and update INDEX.md.
  --staged --stdout  Render Git-index cards to stdout for the commit gate.
  --check             Compare working-tree cards with INDEX.md; do not write.
  --repo PATH         Operate on another repository (used by integration tests).`;
}

function parseArgs(argv) {
  const options = { root: defaultRoot, staged: false, stdout: false, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--repo') {
      const value = argv[index + 1];
      if (!value) throw new Error('--repo requires a path');
      options.root = resolve(value);
      index += 1;
    } else if (arg === '--staged') {
      options.staged = true;
    } else if (arg === '--stdout') {
      options.stdout = true;
    } else if (arg === '--check') {
      options.check = true;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  if (options.check && (options.staged || options.stdout)) {
    throw new Error('--check cannot be combined with --staged or --stdout');
  }
  if (options.staged !== options.stdout) {
    throw new Error('--staged and --stdout must be used together');
  }
  return options;
}

export function run(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return 0;
  }

  const rows = collectRows(options);
  const rendered = renderIndex(rows);
  const outputPath = join(options.root, INDEX_RELATIVE);

  if (options.stdout) {
    process.stdout.write(rendered);
    return 0;
  }
  if (options.check) {
    let existing = '';
    try {
      existing = readFileSync(outputPath, 'utf8');
    } catch {
      // A missing output is stale.
    }
    if (existing !== rendered) {
      process.stderr.write('Punch-card Index is stale. Run `npm run docs:punchcards` and commit the result.\n');
      return 1;
    }
    process.stdout.write(`Punch-card Index is current (${rows.length} cards).\n`);
    return 0;
  }

  let existing = '';
  try {
    existing = readFileSync(outputPath, 'utf8');
  } catch {
    // First generation writes the file.
  }
  if (existing !== rendered) writeFileSync(outputPath, rendered);
  const ins = rows.filter((row) => row.kind === 'in').length;
  const outs = rows.length - ins;
  process.stdout.write(`Wrote ${relative(options.root, outputPath)} — ${rows.length} cards (${ins} in / ${outs} out).\n`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(scriptPath)) {
  try {
    process.exitCode = run();
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
