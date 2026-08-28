#!/bin/sh
# Repo Forensics 101 — Almanac commit-gate installer
# Vendors the almanac scripts into <repo>/scripts/almanac/ and installs a
# pre-commit hook that regenerates docs/ALMANAC.md on every commit.
#
# Per-repo tuning lives in the vendored <repo>/scripts/almanac/config.sh, which is
# seeded once and never overwritten on re-install. It must be COMMITTED: the hook
# runs with a bare environment, so an exported knob survives one manual run and is
# then silently overwritten by the gate's default-configured regeneration.
#
# Gate semantics (environment, read at commit time):
#   GENERATED_DOCS_GATE=off — skip the almanac and every repo-local generated-doc
#                             extension (escape hatch for history surgery).
#   ALMANAC_GATE=stage      — regenerate and stage the almanac (default).
#   ALMANAC_GATE=off        — skip only the almanac; extensions still run.
#
# There is deliberately no "check/verify" mode. Every commit changes the
# arithmetic, so at pre-commit time the committed copy ALWAYS differs from a
# fresh generation by one commit's worth of history. A staleness check would
# therefore fail on every commit — it cannot distinguish stale from current.
# Regeneration is the only honest gate for a page of this kind.
#
# The hook is local, offline, read-only against history, and deterministic. The
# almanac block stages exactly one file. Repositories may register additional
# executable gates under scripts/generated-docs/pre-commit.d/; those extensions
# own and document their staging/failure semantics.
# Usage: install-gate.sh <repo-path>
set -e
bindir=$(cd "$(dirname "$0")" && pwd)
repo="${1:?usage: install-gate.sh <repo-path>}"

git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "install-gate: $repo is not a git repository." >&2; exit 1; }
# Take both paths from git so their spelling is internally consistent; a repo
# reached through a differently-cased path on a case-insensitive filesystem
# would otherwise fail every string comparison below.
repo=$(git -C "$repo" rev-parse --show-toplevel)
gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)

# Directory identity by inode, not by string: on macOS the same directory can be
# spelled /Users/x/Projects/Foo or /users/x/projects/foo and both resolve.
same_dir() {
  [ -d "$1" ] && [ -d "$2" ] || return 1
  _a=$(ls -di "$1" 2>/dev/null | awk '{print $1}')
  _b=$(ls -di "$2" 2>/dev/null | awk '{print $1}')
  [ -n "$_a" ] && [ "$_a" = "$_b" ]
}

# Honor core.hooksPath when set — it may point at the default .git/hooks (a no-op
# reconfiguration) or at a tracked dir like .husky. Resolve it rather than refusing.
hookspath=$(git -C "$repo" config core.hooksPath || true)
if [ -n "$hookspath" ]; then
  case "$hookspath" in /*) hooksdir="$hookspath" ;; *) hooksdir="$repo/$hookspath" ;; esac
else
  hooksdir="$gitdir/hooks"
fi
mkdir -p "$hooksdir"
same_dir "$hooksdir/.." "$gitdir" || \
  echo "install-gate: note — core.hooksPath resolves outside .git ($hooksdir); the hook will be a TRACKED repo file, not local-only." >&2

target="$repo/scripts/almanac"
mkdir -p "$target" "$repo/docs"
# install-gate.sh vendors ITSELF: git hooks are not cloned, so a fresh clone must be
# able to re-arm the gate from inside the repo (`sh scripts/almanac/install-gate.sh .`)
# without reaching back to the campus checkout. When invoked from that vendored copy,
# source and destination are the same directory — copying would be cp-onto-itself, so
# skip straight to arming the hook.
if same_dir "$bindir" "$target"; then
  self_arm=1
  echo "install-gate: running from the vendored copy — re-arming hook only." >&2
else
  self_arm=0
  for f in 01-genesis.sh 02-cadence.sh 03-eras.sh 04-breakage.sh 05-churn.sh almanac.sh install-gate.sh; do
    cp "$bindir/$f" "$target/$f"
  done
  # config.sh is per-repo tuning, not generator code — seed it once, never clobber.
  # Re-running this installer to pick up an upstream fix must not silently reset a
  # repo's fix pattern to the default, which would look like nothing happened while
  # halving its breakage numbers.
  if [ -e "$target/config.sh" ]; then
    echo "install-gate: kept existing $target/config.sh" >&2
  else
    cp "$bindir/config.sh" "$target/config.sh"
  fi
fi
# config.sh is sourced, not run, so it is deliberately left non-executable.
chmod +x "$target"/0*.sh "$target/almanac.sh" "$target/install-gate.sh"

hook="$hooksdir/pre-commit"
if [ -e "$hook" ] && ! grep -q "almanac-gate" "$hook" 2>/dev/null; then
  echo "install-gate: $hook exists and is not an almanac gate — refusing to overwrite." >&2
  exit 1
fi

cat > "$hook" <<'EOF'
#!/bin/sh
# almanac-gate v2 — Almanac plus repo-local generated-doc extensions
[ "${GENERATED_DOCS_GATE:-stage}" = "off" ] && exit 0
root=$(git rev-parse --show-toplevel)

# Almanac keeps its historical best-effort contract: no HEAD on an initial
# commit, a missing generator, or a generator failure never blocks the commit.
if [ "${ALMANAC_GATE:-stage}" != "off" ] \
   && git rev-parse HEAD >/dev/null 2>&1 \
   && [ -x "$root/scripts/almanac/almanac.sh" ]; then
  almanac_tmp=$(mktemp)
  if "$root/scripts/almanac/almanac.sh" "$root" > "$almanac_tmp" \
     && [ -s "$almanac_tmp" ]; then
    # Write only when content changed, but ALWAYS stage: a manually generated
    # file may match the working tree while remaining unstaged.
    cmp -s "$almanac_tmp" "$root/docs/ALMANAC.md" 2>/dev/null \
      || cp "$almanac_tmp" "$root/docs/ALMANAC.md"
    git add "$root/docs/ALMANAC.md"
  fi
  rm -f "$almanac_tmp"
fi

# Extensions are tracked repo policy, run in bytewise filename order. Their
# exit status is authoritative: a fail-closed extension can block the commit,
# while a best-effort extension can return success after warning.
export LC_ALL=C
for generated_gate in "$root"/scripts/generated-docs/pre-commit.d/*.sh; do
  [ -x "$generated_gate" ] || continue
  "$generated_gate" || exit $?
done
exit 0
EOF
chmod +x "$hook"
if [ "$self_arm" = "1" ]; then
  echo "install-gate: armed $hook"
else
  echo "install-gate: vendored scripts to $target/ and armed $hook"
fi
