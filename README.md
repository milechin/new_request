# New Request
## Description

As an HPC facilitator I assist researchers troubleshooting their code or optimizing their code.  To keep my work organized I created this bash script that generates a directory structure to support my work for any new request I recieve.  

## Requirements

Git needs to be installed. For helper scripts generated, they use LMOD module load commands.

## Usage

```console
Syntax: new_request.sh CLIENT TICKET DIR
Arguments:
    CLIENT     A client identifier (e.g. username).
    TICKET     Request identifier (e.g. ticket number).
    DIR        Location to create directory hierarchy (if blank defaults to pwd).
```

The bash script will create a new request directory using the CLIENT and TICKET arguments as unique identifiers.  The directory will be initialized as a git repository.  For example, running the example command below will create a directory "bob/123456" in the current working directory:

```console
bash new_request.sh bob 123456
Initialized empty Git repository in /projectnb/dvm-rcs/client/bob/123456/.git/
```

The script will also generate a `.gitignore` file with the following contents:

https://github.com/milechin/new_request/blob/a57c0438959f6d932095db86f053476db39b7a09/new_request.sh#L74-L76

Additionally, two helper bash scripts will be generated in the `env_setup` directory.  

 - `env_setup/r_env.sh`
https://github.com/milechin/new_request/blob/ee0cd68a4b3f087c7cfc345e55af96c1aa75af0f/new_request.sh#L85-L96

- `env_setup/py_virtenv.sh`
https://github.com/milechin/new_request/blob/ee0cd68a4b3f087c7cfc345e55af96c1aa75af0f/new_request.sh#L140-L147

## Directory Structure

Below is the directory structure the bash script will create:

- *data* - Directory to store relevant data used by the client's scripts.
- *env_setup* - Directory to store scripts files associated with setting up the enviroment for the request at hand.
- *scripts* - Directory to store the client's scripts.
- *output* - Directory to store the output data generated by the client's scripts.
