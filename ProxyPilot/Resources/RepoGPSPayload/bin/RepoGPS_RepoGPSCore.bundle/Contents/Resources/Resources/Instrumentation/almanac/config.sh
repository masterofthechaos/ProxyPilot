# Repo Forensics 101 — per-repo almanac configuration
#
# WHY THIS FILE IS COMMITTED, AND WHY THAT IS THE WHOLE POINT
# The pre-commit gate runs almanac.sh in a bare environment. A knob exported in
# your shell therefore survives exactly one manual regeneration: the next commit
# regenerates the page with the built-in defaults and stages that over your
# tuned copy. Nothing errors, nothing warns — the page still looks maintained,
# it is just maintained wrong. A committed file is the only form of
# configuration a hook running in a clean environment can see.
#
# PRECEDENCE: environment > this file > built-in default in the unit script.
# Every line below uses `: "${VAR:=value}"`, which assigns only when VAR is
# unset, so a deliberate one-off still wins:
#     ALMANAC_FIX_WINDOW_DAYS=30 sh scripts/almanac/almanac.sh .
#
# This file is sourced, not executed. Keep it to variable assignments — it runs
# inside the generator on every commit, so anything with a side effect here is a
# side effect of committing.

# ERE for "this commit admits it fixed something", matched against the
# LOWERCASED commit subject. Write patterns in lower case; `[Ff]ix` is
# redundant. Tune this to how THIS repo actually words its fixes:
#   - conventional commits ("fix: ...")      → the anchored default is right
#   - prose subjects ("v1.2.3: fix the ...") → anchoring under-reports by half
# The proxy's honesty is downstream of commit discipline, so an untuned pattern
# does not report "no breakage" — it reports "no breakage I was told to look for".
: "${ALMANAC_FIX_PATTERN:=^(fix|hotfix|revert)}"

# Days after a tag during which a fix commit counts against that release.
: "${ALMANAC_FIX_WINDOW_DAYS:=14}"
