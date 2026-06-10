#!/bin/bash -l
#
# r_install.sh <package> [workspace]
#
# Reproduce a researcher's R package install inside the request workspace and
# report a CLASSIFIED outcome (via triage_build_log.sh) -- not a raw log dump.
# Run it (do not source).
#
#   <package>    R package to install (e.g. RcppEigen).
#   [workspace]  request directory (default: current directory).
#
# Prereq: the workspace's R env must be set up (run `r_env.sh R/X.Y <ws>` once).

# No `set -u`: sourcing module_load.sh runs the Lmod `module` function.
set -eo pipefail

PKG="${1:-}"
WORKSPACE="${2:-$PWD}"
[ -n "$PKG" ] || { printf 'Usage: r_install.sh <package> [workspace]\n' >&2; exit 2; }
WORKSPACE="$(cd "$WORKSPACE" 2>/dev/null && pwd)" || { printf 'ERROR: no such workspace: %s\n' "${2:-$PWD}" >&2; exit 2; }
[ -f "$WORKSPACE/module_load.sh" ] || { printf 'ERROR: %s is not a request workspace (no module_load.sh)\n' "$WORKSPACE" >&2; exit 2; }

# Locate the sibling triage tool (bin/triage_build_log.sh) regardless of PATH.
TRIAGE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/triage_build_log.sh"

cd "$WORKSPACE"

# Activate the environment. BARE `source` -- never piped, never `$(...)`, never
# `source ... | tail`: a pipe runs source in a subshell, so `module load` and the
# exports never reach this shell and R never actually loads.
source ./module_load.sh

if ! command -v R >/dev/null 2>&1 || [ -z "${R_LIBS_USER:-}" ]; then
  printf 'ERROR: R / R_LIBS_USER not available after sourcing module_load.sh.\n' >&2
  printf '       Set up the R environment first:  r_env.sh R/<version> %s\n' "$WORKSPACE" >&2
  exit 1
fi

mkdir -p output
LOG="output/${PKG}_install.log"
printf "Installing '%s' into %s\n  log: %s\n\n" "$PKG" "$R_LIBS_USER" "$LOG"

# Capture ALL output; never abort on install failure -- we want to triage it.
R --vanilla --quiet -e "install.packages('${PKG}', repos='https://cloud.r-project.org', Ncpus=1)" > "$LOG" 2>&1 || true

if [ -d "${R_LIBS_USER%/}/${PKG}" ]; then PRESENT=yes; else PRESENT=no; fi
if R --vanilla --quiet -e "library(${PKG})" >/dev/null 2>&1; then LOADS=yes; else LOADS=no; fi
printf "Package '%s':  present=%s  loads=%s\n\n" "$PKG" "$PRESENT" "$LOADS"

# Classified triage of the install log.
if [ -x "$TRIAGE" ]; then
  "$TRIAGE" "$LOG" || true
else
  printf '(triage tool not found at %s; raw log: %s)\n' "$TRIAGE" "$LOG"
fi
