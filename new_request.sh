#!/bin/bash -l

CLIENT=$1	# Client identifier (e.g. username)
TICKET=$2	# Ticket number
DIR=$3		# Location where to create new request directory


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

# If the DIR argument is not provided
# then use the current working directory
# for the location of the new request 
# environment creation.
if [[ -z "${DIR}" ]]; then
  DIR=${PWD}
fi

# Check for valid arguments
if [ -z "$CLIENT" ]
  then
    printf "CLIENT not provided \n\n"
    Help
    exit 1
fi

if [ -z "$TICKET" ]
  then
    printf "TICKET not provided \n\n"
    Help
    exit 1
fi

# Assemble the new request environment directory
NEW_DIR=${DIR}/${CLIENT}/${TICKET}

# Check if the request directory already exists
if [ -d ${NEW_DIR} ]; then
    printf "Directory already exists: \n ${NEW_DIR}\n"
    Help
    exit 1
fi


# Create new directory and structure for the new request.
mkdir -p ${NEW_DIR}
cd ${NEW_DIR}

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

# TODO: #3 Add bash helper scripts to .gitignore
cat > .gitignore << EOF
data/
.gitignore
output/
env_setup/r_env.sh
env_setup/py_virtenv.sh
.venv
.conda
EOF

# Create am sh script to specify modules and environment.
SCC_ENV_FILE=module_load.sh 
echo "#!/usr/bin/bash -l" > ${NEW_DIR}/${SCC_ENV_FILE} 

# Create a helper bash script for creating
# an isolated R environment, which can be sourced
# when needed.
cat > env_setup/r_env.sh << EOF
#!/bin/bash -l

# DESCRIPTION
# Load an R module and set the $R_LIBS_USER environment
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

# Check if an R Module was specified as an argument.

if [ -z "\$R_MODULE" ]; then
  # If R Module is not provided as an argument, use 
  # the default values.

  R_MODULE=\${R_MODULE_DEFAULT}
  R_DIR=${NEW_DIR}/\${R_DEFAULT_DIR}/

else

  R_DIR=${NEW_DIR}/\${R_MODULE}/

fi

# Load the R module and set the \$R_LIBS_USER path
module load \${R_MODULE}
EXIT_CODE=\$?

if [ \${EXIT_CODE} -eq 0 ]; then
  export R_LIBS_USER=\${R_DIR}


  # Check if the \$R_LIBS_USER directory exits.
  # If not, create it.
  if [ ! -d \${R_LIBS_USER} ]; then
      mkdir -p \${R_LIBS_USER}
  fi

  if ! grep -Fxq "\${R_MODULE}" ${NEW_DIR}/.gitignore
  then
      # Add the library directory to gitignore
      echo \${R_MODULE} >> ${NEW_DIR}/.gitignore
  fi

  # Create an activate script for this environment
  echo "module load \${R_MODULE}" >> ${NEW_DIR}/${SCC_ENV_FILE} 
  echo "export R_LIBS_USER=\${R_DIR}" >> ${NEW_DIR}/${SCC_ENV_FILE} 

  # Outputing information about the environment.
  echo "echo Activating R Environment" >> ${NEW_DIR}/${SCC_ENV_FILE} 
  echo "R_LIBS_USER=\${R_LIBS_USER}" >> ${NEW_DIR}/${SCC_ENV_FILE}
  echo "module list" >>  ${NEW_DIR}/${SCC_ENV_FILE} 

  # Add the module_load.sh file to .gitignore
  echo \${SCC_ENV_FILE} >> ${NEW_DIR}/.gitignore

  # Install R Packages required for VSCode usage
  R -e "install.packages(c('languageserver'), lib='\${R_LIBS_USER}', repos='https://cran.rstudio.com/')"
  R -e "install.packages('vscDebugger', repos = 'https://manuelhentschel.r-universe.dev')"

else
  printf "ERROR: Failed to load module \${R_MODULE}.\n\n"
fi

EOF



# Initialize the new request directory as a git repository
# to track changes as the code is modified.
git init


