# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`new_request.sh` is a single bash script used by an HPC facilitator (Boston University SCC) to scaffold a directory hierarchy for each new researcher support request. There is no build system, no dependencies to install, and no application — the entire project is this one script plus its generated output.

## Running

```console
bash new_request.sh CLIENT TICKET [DIR]
```

Creates `${DIR}/${CLIENT}/${TICKET}/` (DIR defaults to `pwd`), populates it with `data/`, `env_setup/`, `scripts/`, `output/`, a `.gitignore`, an empty `module_load.sh`, an `env_setup/r_env.sh` helper, and runs `git init` inside it. The script exits with status 1 (and prints `Help`) if CLIENT or TICKET is missing, or if the target directory already exists.

## Testing

There is no test framework. The `test/` directory is committed sample output from a real run (`test/inc1234/`) — it is a generated artifact, not a test suite. To verify changes, run the script into a throwaway directory and inspect the result:

```console
bash new_request.sh testclient testticket /tmp
```

## Architecture: generated-script escaping

The single most error-prone aspect of this code is that `new_request.sh` *generates* another script (`env_setup/r_env.sh`) via a `cat > ... << EOF` heredoc. Inside that heredoc there are two classes of variables, and the distinction is load-bearing:

- **Unescaped** (e.g. `${NEW_DIR}`, `${SCC_ENV_FILE}`) — expanded *now*, at generation time, so the generated script contains absolute paths baked in. See how `test/inc1234/env_setup/r_env.sh` has the full `/projectnb/...` path hardcoded.
- **Escaped with `\$`** (e.g. `\$R_MODULE`, `\$R_LIBS_USER`, `\$EXIT_CODE`) — written literally into `r_env.sh` and only expanded when the *generated* script runs.

When editing the heredoc, always decide whether a variable should resolve at generation time or run time, and escape accordingly. A common bug is forgetting the backslash, which silently bakes in an empty/wrong value (note line 98 of `new_request.sh`: `$R_LIBS_USER` in a comment is unescaped and expands at generation time — visible in the test output's mangled comment).

## What the generated `r_env.sh` does

The generated helper is meant to be `source`d (`source env_setup/r_env.sh R/4.4.0`), not executed. It:
1. Loads the given LMOD R module (default `R`), and on success sets `R_LIBS_USER` to a per-module library dir inside the request folder, creating it if needed.
2. Appends `module load` + `export R_LIBS_USER` lines to `module_load.sh` (the project's persistent environment-activation script).
3. Adds the module's library dir and `module_load.sh` to `.gitignore`.
4. Installs `languageserver` and `vscDebugger` so the request can be worked on in VSCode.

This depends on the LMOD `module` command being available (BU SCC environment).
