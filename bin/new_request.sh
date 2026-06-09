#!/bin/bash -l

set -euo pipefail

# Repo root (the parent of this script's bin/ directory), resolved before any
# cd, so bundled templates (templates/CLAUDE.md, templates/context/,
# templates/init-request.md) can be located and copied/symlinked into the new
# workspace, and so the bin/ scripts can be referenced.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLIENT="${1:-}"	# Client identifier (e.g. username)
TICKET="${2:-}"	# Ticket number
DIR="${3:-}"	# Location where to create new request directory


# Help function with instructions on how to use this script.
Help()
{
   # Display Help
   echo "HELP"
   echo "Description: Creates a directory hierarchy for a "
   echo " new request"
   echo
   echo "Syntax: $(basename $0) CLIENT TICKET DIR"
   echo "Arguments:"
   echo "    CLIENT     A client identifier (e.g. username)."
   echo "    TICKET     Request identifier (e.g. ticket number)."
   echo "    DIR        Location to create directory hierarchy (if blank defaults to pwd)."
   echo
}

# Show help and exit if requested.
case "${1:-}" in
  -h|--help) Help; exit 0 ;;
esac

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
.claude/
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

# Make the /init-request slash command available in this workspace by symlinking
# it from this repo, so updates to the command propagate to every request. The
# symlink is an absolute path into this repo, so .claude/ is gitignored (an
# absolute-path symlink should not be committed); discovery is unaffected.
if [ -f "${REPO_DIR}/templates/init-request.md" ]; then
  mkdir -p .claude/commands
  ln -sf "${REPO_DIR}/templates/init-request.md" .claude/commands/init-request.md
else
  printf "WARNING: template not found: %s/templates/init-request.md\n" "${REPO_DIR}"
fi



# Initialize the new request directory as a git repository
# to track changes as the code is modified.
git init

# Point the facilitator at the next steps. The R helpers live in this repo's
# bin/; with that on PATH they can be run from any workspace.
cat << MSG

Created request workspace: ${NEW_DIR}

To set up an R environment for it (with ${REPO_DIR}/bin on your PATH):
  r_env.sh R/4.5.2 "${NEW_DIR}"        # one-time setup
  source "${NEW_DIR}/module_load.sh"   # activate this + future sessions
  # scp the researcher's R library into the R_LIBS_USER shown above
  r_snapshot.sh "${NEW_DIR}"           # record env_setup/renv.lock
MSG
