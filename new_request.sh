#!/bin/bash -l

set -euo pipefail

# Directory containing this script, resolved before any cd, so bundled
# templates (e.g. templates/r_snapshot.sh) can be located and copied in.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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



# Create a gitignore file for known files we don't
# want to track using git.
cat > .gitignore << EOF
data/
.gitignore
output/
env_setup/r_env.sh
env_setup/r_snapshot.sh
env_setup/.renv-tools/
module_load.sh
.venv
.conda
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

# Create a helper bash script for creating
# an isolated R environment, which can be sourced
# when needed.
cat > env_setup/r_env.sh << EOF
#!/bin/bash -l

# DESCRIPTION
# Load an R module and set the \$R_LIBS_USER environment
# variable so that any R packages installed will
# be installed in the new request directory.

# Source this r_env.sh file before starting R so
# only R packages associated with this request environment
# are available during the R session

# Example command:
#   source env_setup/r_env.sh R/4.4.0
#

## ARGUMENTS ##
R_MODULE=\$1		# Define a specific module to load

## DEFAULTS ##
R_MODULE_DEFAULT=R	# Define a default module to load if no
			# module is provided as argument.
R_DEFAULT_DIR=\${R_MODULE_DEFAULT}/default  # Define a default library location for default R module.
			# NOTE: 'R/default' tracks whatever the cluster's default R module
			# was at setup time. If that default later changes, packages cached
			# here may not load under the new version -- pass an explicit
			# version (e.g. R/4.4.0) for a longer-lived environment.

# Check if an R Module was specified as an argument.

if [ -z "\$R_MODULE" ]; then
  # If R Module is not provided as an argument, use
  # the default values.

  R_MODULE=\${R_MODULE_DEFAULT}
  R_DIR="${NEW_DIR}/\${R_DEFAULT_DIR}/"

else

  R_DIR="${NEW_DIR}/\${R_MODULE}/"

fi

# Load the R module and set the \$R_LIBS_USER path
module load \${R_MODULE}
EXIT_CODE=\$?

if [ "\${EXIT_CODE}" -eq 0 ]; then
  export R_LIBS_USER="\${R_DIR}"


  # Check if the \$R_LIBS_USER directory exits.
  # If not, create it.
  if [ ! -d "\${R_LIBS_USER}" ]; then
      mkdir -p "\${R_LIBS_USER}"
  fi

  if ! grep -Fxq "\${R_MODULE}" "${NEW_DIR}/.gitignore"
  then
      # Add the library directory to gitignore
      echo "\${R_MODULE}" >> "${NEW_DIR}/.gitignore"
  fi

  # Append the R activation block to module_load.sh (once). The marker guard
  # keeps re-sourcing this script idempotent. Variables are expanded now (at
  # r_env.sh run time) so literal values are baked into module_load.sh.
  if ! grep -Fq "# >>> R environment" "${NEW_DIR}/${SCC_ENV_FILE}"; then
    cat >> "${NEW_DIR}/${SCC_ENV_FILE}" << BLOCK

# >>> R environment (added by r_env.sh during setup) >>>
module load \${R_MODULE}
export R_LIBS_USER="\${R_DIR}"
echo "Activating R environment"
echo "R_LIBS_USER=\${R_LIBS_USER}"
module list
# <<< R environment <<<
BLOCK
  fi

  # Install R Packages required for VSCode usage
  R -e "install.packages(c('languageserver'), lib='\${R_LIBS_USER}', repos='https://cran.rstudio.com/')"
  R -e "install.packages('vscDebugger', repos = 'https://manuelhentschel.r-universe.dev')"

  # Tell the user how to reproduce a researcher's R environment from here.
  echo
  echo "R environment ready.  R_LIBS_USER=\$R_LIBS_USER"
  echo "To reproduce a researcher's R environment for debugging:"
  echo "  1. scp their R library into:  \$R_LIBS_USER"
  echo "  2. Record a manifest:         bash env_setup/r_snapshot.sh"

else
  printf "ERROR: Failed to load module \${R_MODULE}.\n\n"
fi

EOF

# Copy the renv snapshot helper into the request's env_setup directory.
# It records the reproduced R library into env_setup/renv.lock (see the script
# header). It is path-independent (reads $R_LIBS_USER at run time).
if [ -f "${SCRIPT_DIR}/templates/r_snapshot.sh" ]; then
  cp "${SCRIPT_DIR}/templates/r_snapshot.sh" env_setup/r_snapshot.sh
else
  printf "WARNING: template not found: %s/templates/r_snapshot.sh\n" "${SCRIPT_DIR}"
fi



# Initialize the new request directory as a git repository
# to track changes as the code is modified.
git init
