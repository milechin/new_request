#!/bin/bash -l

set -euo pipefail

# Repo root (the parent of this script's bin/ directory), resolved before any
# cd, so bundled templates (templates/CLAUDE.md, templates/context/,
# templates/init-request.md) can be located and copied/symlinked into the new
# workspace, and so the bin/ scripts can be referenced.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Help function with instructions on how to use this script.
Help()
{
   # Display Help
   echo "HELP"
   echo "Description: Creates a directory hierarchy for a new request."
   echo
   echo "Syntax: $(basename "$0") CLIENT TICKET [DIR] [--lang LANGS]"
   echo "Arguments:"
   echo "    CLIENT     A client identifier (e.g. username)."
   echo "    TICKET     Request identifier (e.g. ticket number)."
   echo "    DIR        Location to create directory hierarchy (default: pwd)."
   echo "    --lang     Comma-separated language toolset(s) to activate, e.g."
   echo "               --lang r   or   --lang r,python . Puts bin/<lang> on"
   echo "               PATH when the workspace's module_load.sh is sourced."
   echo
}

# Parse arguments: positional CLIENT TICKET [DIR], optional --lang, and -h/--help.
LANGS=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) Help; exit 0 ;;
    --lang)    LANGS="${2:-}"; shift 2 ;;
    --lang=*)  LANGS="${1#--lang=}"; shift ;;
    *)         POSITIONAL+=("$1"); shift ;;
  esac
done
if [ ${#POSITIONAL[@]} -gt 0 ]; then set -- "${POSITIONAL[@]}"; fi

CLIENT="${1:-}"   # Client identifier (e.g. username)
TICKET="${2:-}"   # Ticket number
DIR="${3:-}"      # Location where to create the new request directory

# If the DIR argument is not provided
# then use the current working directory
# for the location of the new request
# environment creation.
if [[ -z "${DIR}" ]]; then
  DIR="${PWD}"
fi

# Check for valid arguments
if [ -z "${CLIENT}" ]
  then
    printf "CLIENT not provided \n\n"
    Help
    exit 1
fi

if [ -z "${TICKET}" ]
  then
    printf "TICKET not provided \n\n"
    Help
    exit 1
fi

# Reject identifiers that could escape the intended
# DIR/CLIENT/TICKET directory layout.
if [[ "${CLIENT}" == */* || "${TICKET}" == */* || "${CLIENT}" == *..* || "${TICKET}" == *..* ]]; then
    printf "ERROR: CLIENT and TICKET must not contain '/' or '..'\n\n"
    Help
    exit 1
fi

# Assemble the new request environment directory
NEW_DIR="${DIR}/${CLIENT}/${TICKET}"

# Check if the request directory already exists
if [ -d "${NEW_DIR}" ]; then
    printf "Directory already exists: \n %s\n" "${NEW_DIR}"
    Help
    exit 1
fi


# Create new directory and structure for the new request.
mkdir -p "${NEW_DIR}"
cd "${NEW_DIR}" || { printf "ERROR: could not cd into %s\n" "${NEW_DIR}"; exit 1; }

mkdir -p data		# Directory to store relevant data used
			# by the client's scripts
mkdir -p env_setup	# Directory to store scripts files associated
			# with setting up the enviroment for
			# the request at hand
mkdir -p scripts	# Directory to store the client's scripts
mkdir -p output		# Directory to store any outputs generated
			# by the client's scripts.
mkdir -p context	# Directory for the problem description and
			# relevant links Claude should use as context.



# Create a gitignore file for known files we don't
# want to track using git.
cat > .gitignore << EOF
data/
.gitignore
output/
env_setup/.renv-tools/
module_load.sh
.venv
.conda
.cache/
.config/
.local/
.renv/
.Rhistory
.claude
EOF

# Create the activation script that specifies modules and environment.
# Source it (do not execute) to activate the request's environment.
SCC_ENV_FILE=module_load.sh
cat > "${NEW_DIR}/${SCC_ENV_FILE}" << 'EOF'
#!/bin/bash -l
#
# module_load.sh -- activation script for this request.
# SOURCE it (do not execute) to load modules and set environment variables:
#     source module_load.sh
# r_env.sh appends an R environment block during setup. Add any additional
# `module load` lines or environment settings below as needed.
#
EOF

# Contain package/tool caches, config, data, and history inside this request
# workspace instead of the user's home directory. Baked absolute paths; the
# runtime ($XDG_*) references stay literal so they resolve when sourced.
cat >> "${NEW_DIR}/${SCC_ENV_FILE}" << EOF

# Keep caches/config/data/history in this workspace instead of \$HOME
# (~/.cache, ~/.config, ~/.local/share). Best-effort: this redirects tools that
# honor XDG / tools::R_user_dir(); scripts that hardcode ~ or an absolute home
# path can still escape (use a container or throwaway user for hard isolation).
export XDG_CACHE_HOME="${NEW_DIR}/.cache"
export XDG_CONFIG_HOME="${NEW_DIR}/.config"
export XDG_DATA_HOME="${NEW_DIR}/.local/share"
export XDG_STATE_HOME="${NEW_DIR}/.local/state"
export RENV_PATHS_ROOT="${NEW_DIR}/.renv"
export R_ENVIRON_USER="${NEW_DIR}/.Renviron"
export R_PROFILE_USER="${NEW_DIR}/.Rprofile"
export R_HISTFILE="${NEW_DIR}/.Rhistory"
mkdir -p "\$XDG_CACHE_HOME" "\$XDG_CONFIG_HOME" "\$XDG_DATA_HOME" "\$XDG_STATE_HOME" "\$RENV_PATHS_ROOT"
EOF

# Activate the selected language toolset(s): when module_load.sh is sourced, put
# this repo's bin/<lang> on PATH so the language's tools are available. Chosen at
# creation via --lang (comma-separated); edit module_load.sh later to change.
if [ -n "${LANGS}" ]; then
  IFS=',' read -ra _LANGS <<< "${LANGS}"
  for _lang in "${_LANGS[@]}"; do
    _lang="$(echo "${_lang}" | tr -d '[:space:]')"
    [ -z "${_lang}" ] && continue
    if [ -d "${REPO_DIR}/bin/${_lang}" ]; then
      {
        echo ""
        echo "# >>> ${_lang} toolset (added by new_request.sh --lang) >>>"
        echo "export PATH=\"${REPO_DIR}/bin/${_lang}:\$PATH\""
        echo "# <<< ${_lang} toolset <<<"
      } >> "${NEW_DIR}/${SCC_ENV_FILE}"
    else
      printf "WARNING: unknown language toolset '%s' (no %s) -- skipping\n" \
             "${_lang}" "${REPO_DIR}/bin/${_lang}"
    fi
  done
fi

# Add a per-request CLAUDE.md describing the workspace structure, so Claude has
# context when helping troubleshoot. Tracked in git (durable request doc).
if [ -f "${REPO_DIR}/templates/CLAUDE.md" ]; then
  cp "${REPO_DIR}/templates/CLAUDE.md" CLAUDE.md
else
  printf "WARNING: template not found: %s/templates/CLAUDE.md\n" "${REPO_DIR}"
fi

# Seed the context/ directory with templates for the problem description and
# relevant links (the facilitator fills these in; /init-request reads them).
if [ -d "${REPO_DIR}/templates/context" ]; then
  cp "${REPO_DIR}/templates/context/"*.md context/
else
  printf "WARNING: template dir not found: %s/templates/context\n" "${REPO_DIR}"
fi

# Symlink this repo's whole .claude/ into the workspace, so every Claude asset it
# holds (commands like /init-request, plus any skills/ or agents/ added later) is
# available here automatically -- no re-scaffolding when the repo gains new ones.
# The symlink is an absolute path into this repo, so .claude is gitignored (an
# absolute-path symlink should not be committed); discovery is unaffected.
if [ -d "${REPO_DIR}/.claude" ]; then
  ln -s "${REPO_DIR}/.claude" .claude
else
  printf "WARNING: shared Claude dir not found: %s/.claude\n" "${REPO_DIR}"
fi



# Initialize the new request directory as a git repository
# to track changes as the code is modified.
git init

# Point the facilitator at the next steps. Language tools live in this repo's
# bin/<lang>/ and are put on PATH by the workspace's module_load.sh (per --lang).
cat << MSG

Created request workspace: ${NEW_DIR}
Activated language toolset(s): ${LANGS:-none (add with --lang, or edit module_load.sh)}

Next steps:
  source "${NEW_DIR}/module_load.sh"     # activate env + put bin/<lang> on PATH
  # --- for an R request ---
  r_env.sh R/4.5.2 "${NEW_DIR}"          # one-time R setup
  source "${NEW_DIR}/module_load.sh"     # re-source to load the R env it recorded
  # scp the researcher's R library into the R_LIBS_USER shown on activation
  r_snapshot.sh "${NEW_DIR}"             # record env_setup/renv.lock
MSG
