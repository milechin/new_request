#!/bin/bash -l

# DESCRIPTION
# One-time setup of an isolated R environment for a request workspace:
#   - loads the given R module,
#   - creates a per-module package library inside the workspace,
#   - installs the R packages VSCode needs (languageserver, vscDebugger),
#   - records the module + library in the workspace's module_load.sh and .gitignore.
#
# This script is RUN, not sourced. It does NOT change your current shell --
# activate the environment afterwards with:
#   source <workspace>/module_load.sh
#
# USAGE
#   r_env.sh [R_MODULE] [WORKSPACE]
#     R_MODULE   R module to load (default: R, the cluster default).
#     WORKSPACE  Request directory to set up (default: current directory).
#
# EXAMPLES
#   cd /path/to/request && r_env.sh R/4.5.2
#   r_env.sh R/4.5.2 /path/to/request

# Note: no `-u` -- the Lmod `module` function is not guaranteed to be safe under
# `set -u`, and the existing activation scripts don't use it either.
set -eo pipefail

R_MODULE="${1:-}"
WORKSPACE="${2:-$PWD}"

# Resolve the workspace to an absolute path and sanity-check it.
if ! WORKSPACE="$(cd "$WORKSPACE" 2>/dev/null && pwd)"; then
  printf "ERROR: workspace directory does not exist: %s\n" "${2:-$PWD}"
  exit 1
fi
if [ ! -f "$WORKSPACE/module_load.sh" ]; then
  printf "ERROR: %s does not look like a request workspace (no module_load.sh).\n" "$WORKSPACE"
  printf "       Create one with new_request.sh, or pass the correct workspace path.\n"
  exit 1
fi

# Determine the module to load and its library directory.
R_MODULE_DEFAULT=R
if [ -z "$R_MODULE" ]; then
  # No module specified: load the cluster default and use a version-agnostic
  # 'R/default' library. NOTE: 'R/default' tracks whatever the cluster's default
  # R is at setup time; pass an explicit version (e.g. R/4.5.2) for longevity.
  R_MODULE="$R_MODULE_DEFAULT"
  R_DIR="$WORKSPACE/$R_MODULE_DEFAULT/default/"
else
  R_DIR="$WORKSPACE/$R_MODULE/"
fi

# Load the R module (affects this script's process only).
if ! module load "$R_MODULE"; then
  printf "ERROR: failed to load module %s\n" "$R_MODULE"
  exit 1
fi

mkdir -p "$R_DIR"

# Record the library dir in the workspace .gitignore (once).
if ! grep -Fxq "$R_MODULE" "$WORKSPACE/.gitignore" 2>/dev/null; then
  echo "$R_MODULE" >> "$WORKSPACE/.gitignore"
fi

# Append the R activation block to module_load.sh (once). The marker guard keeps
# re-running idempotent. Absolute paths are baked in so sourcing works anywhere.
if ! grep -Fq "# >>> R environment" "$WORKSPACE/module_load.sh"; then
  cat >> "$WORKSPACE/module_load.sh" << BLOCK

# >>> R environment (added by r_env.sh during setup) >>>
module load $R_MODULE
export R_LIBS_USER="$R_DIR"
echo "Activating R environment"
echo "R_LIBS_USER=$R_DIR"
module list
# <<< R environment <<<
BLOCK
fi

# Install the R packages required for VSCode usage into the workspace library.
R -e "install.packages(c('languageserver'), lib='$R_DIR', repos='https://cran.rstudio.com/')"
R -e "install.packages('vscDebugger', lib='$R_DIR', repos='https://manuelhentschel.r-universe.dev')"

cat << MSG

R environment setup complete.
  Module:       $R_MODULE
  R library:    $R_DIR

Next steps:
  1. Activate this environment:           source $WORKSPACE/module_load.sh
  2. scp the researcher's R library into: $R_DIR
  3. Record a manifest of it:             r_snapshot.sh $WORKSPACE
MSG
