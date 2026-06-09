#!/bin/bash -l

# DESCRIPTION
# Record the current isolated R library into env_setup/renv.lock -- a manifest
# of exactly what was reproduced for this request (package versions, sources,
# and the R version). renv is used here only to DOCUMENT the library; it does
# not install or change any of the researcher's packages.
#
# PREREQUISITES (in order):
#   1. Source module_load.sh to load the R module and set R_LIBS_USER:
#        source module_load.sh
#      (module_load.sh is the activation script created by env_setup/r_env.sh
#       during the one-time R environment setup.)
#   2. scp the researcher's R library into $R_LIBS_USER. This is done manually
#      by the facilitator (it requires logging in as the researcher) and is NOT
#      automated by this script.
#
# Then run this script from the request directory:
#   bash env_setup/r_snapshot.sh
#
# NOTES
#   - Same-cluster / same-R-module only: the copied packages are compiled for a
#     specific R version and architecture.
#   - renv itself is installed into a separate tools library (.renv-tools) so it
#     does not appear in the manifest -- renv.lock reflects ONLY the researcher's
#     packages.
#   - renv.lock is meant to be committed to git; the reproduced library under
#     R/<version>/ and .renv-tools are gitignored.

set -euo pipefail

# 1. The R environment must be active (step 1 above).
if [ -z "${R_LIBS_USER:-}" ]; then
  printf "ERROR: R_LIBS_USER is not set.\n"
  printf "       Source the activation script first:\n"
  printf "         source module_load.sh\n\n"
  exit 1
fi

# 2. The researcher's library must already be in place (step 2 above).
if [ ! -d "${R_LIBS_USER}" ] || [ -z "$(ls -A "${R_LIBS_USER}" 2>/dev/null)" ]; then
  printf "ERROR: %s is empty.\n" "${R_LIBS_USER}"
  printf "       scp the researcher's R library into it first, then re-run.\n\n"
  exit 1
fi

# Install renv into a dedicated tools library so it stays out of the manifest.
export RENV_TOOLS_LIB="$(pwd)/env_setup/.renv-tools"
mkdir -p "${RENV_TOOLS_LIB}"

# Record the current project library (R_LIBS_USER) into env_setup/renv.lock.
# type="all" captures every installed package, not just those referenced by code.
Rscript -e '
  tools <- Sys.getenv("RENV_TOOLS_LIB")
  proj  <- Sys.getenv("R_LIBS_USER")
  if (!requireNamespace("renv", quietly = TRUE, lib.loc = tools)) {
    install.packages("renv", lib = tools, repos = "https://cran.rstudio.com/")
  }
  library(renv, lib.loc = tools)
  renv::snapshot(library = proj, type = "all",
                 lockfile = file.path("env_setup", "renv.lock"),
                 prompt = FALSE)
'

printf "\nWrote env_setup/renv.lock (manifest of %s).\n" "${R_LIBS_USER}"
printf "Commit renv.lock to record what was reproduced for this request.\n"
