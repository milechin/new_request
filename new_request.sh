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
cat > .gitignore << EOF
data/
.gitignore
output/
EOF

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

  module load \${R_MODULE_DEFAULT}
  export R_LIBS_USER=${NEW_DIR}/env_setup/\${R_DEFAULT_DIR}

  # Add the library directory to gitignore
  echo env_setup/\${R_DEFAULT_DIR}/ >>${NEW_DIR}/.gitignore

else

  # If R module is provided, load that module 
  # and define \$R_LIBS_USER
  # based on this module name.

  module load \${R_MODULE}
  export R_LIBS_USER=${NEW_DIR}/env_setup/\${R_MODULE}

  # Add the library directory to gitignore
  echo env_setup/\${R_MODULE}/ >> ${NEW_DIR}/.gitignore
fi


# Check if the \$R_LIBS_USER directory exits.
# If not, create it.
if [ ! -d \${R_LIBS_USER} ]; then
    mkdir -p \${R_LIBS_USER}
fi

EOF


# Create a helper bash script that can be sourced
# to create a python virtualenv environment.

cat > env_setup/py_virtenv.sh << EOF
#!/bin/bash -l

# DESCRIPTION
# Load a python module and then
# create a virtualenv with site packages
# included.

# Example command:
#   source env_setup/py_virtenv.sh python3/3.12.4
#

## ARGUMENTS ##
PY_MODULE=\$1		# Define a specific module to load

## DEFAULTS ##
PY_MODULE_DEFAULT=python3	# Define a default module to load if no
			# module is provided as argument. 
PY_DEFAULT_DIR=\${PY_MODULE_DEFAULT}/default  # Define a virtualenv path name for the default Python module


# Check if a Python module was specified as an argument.
if [ -z "\$PY_MODULE" ]; then
  # If a Python module is not provided as an argument, use 
  # the default values.
  
  module load \${PY_MODULE_DEFAULT}
  PY_VIRT_DIR=${NEW_DIR}/env_setup/\${PY_DEFAULT_DIR}

  # Add the library directory to gitignore
  echo env_setup/\${PY_DEFAULT_DIR}/ >> ${NEW_DIR}/.gitignore

else

  # If a Python module is provided, load that module 
  # and define \$PY_VIRT_DIR based on the module name

  module load \${PY_MODULE}
  PY_VIRT_DIR=${NEW_DIR}/env_setup/\${PY_MODULE}

  # Add the library directory to gitignore
  echo env_setup/\${PY_MODULE}/ >> ${NEW_DIR}/.gitignore
fi

# Check if the virtual environment already exist at \$PY_VIRT_DIR
# if not, create it.
if [ -d \${PY_VIRT_DIR} ]; then
    printf "Found virtual environment at:\n \${PY_VIRT_DIR}\n"

else
    printf "Creating a virtual environment at:\n \${PY_VIRT_DIR}\n"
    python3 -m venv --system-site-packages \${PY_VIRT_DIR}
fi

# Activate the environment.
source \${PY_VIRT_DIR}/bin/activate

EOF


# Initialize the new request directory as a git repository
# to track changes as the code is modified.
git init


