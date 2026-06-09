# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`new_request.sh` is a single bash script used by an HPC facilitator (Boston University SCC) to scaffold a directory hierarchy for each new researcher support request. There is no build system, no dependencies to install, and no application — the entire project is this one script plus its generated output.

## Running

```console
bash new_request.sh CLIENT TICKET [DIR]
```

Creates `${DIR}/${CLIENT}/${TICKET}/` (DIR defaults to `pwd`), populates it with `data/`, `env_setup/`, `scripts/`, `output/`, a `.gitignore`, an empty `module_load.sh`, an `env_setup/r_env.sh` helper, a copy of `env_setup/r_snapshot.sh` (from `templates/`), and runs `git init` inside it. The script exits with status 1 (and prints `Help`) if CLIENT or TICKET is missing, contains `/` or `..`, or if the target directory already exists; `-h`/`--help` prints help and exits 0.

## Testing

There is no test framework. The `test/` directory is committed sample output from a real run (`test/inc1234/`) — it is a generated artifact, not a test suite. To verify changes, run the script into a throwaway directory and inspect the result:

```console
bash new_request.sh testclient testticket /tmp
```

## Architecture: generated-script escaping

The single most error-prone aspect of this code is that `new_request.sh` *generates* another script (`env_setup/r_env.sh`) via a `cat > ... << EOF` heredoc. Inside that heredoc there are two classes of variables, and the distinction is load-bearing:

- **Unescaped** (e.g. `${NEW_DIR}`, `${SCC_ENV_FILE}`) — expanded *now*, at generation time, so the generated script contains absolute paths baked in. See how `test/inc1234/env_setup/r_env.sh` has the full `/projectnb/...` path hardcoded.
- **Escaped with `\$`** (e.g. `\$R_MODULE`, `\$R_LIBS_USER`, `\$EXIT_CODE`) — written literally into `r_env.sh` and only expanded when the *generated* script runs.

When editing the heredoc, always decide whether a variable should resolve at generation time or run time, and escape accordingly. A common bug is forgetting the backslash, which silently bakes in an empty/wrong value — even in comments. The source-time instruction echoes (e.g. `echo "... \$R_LIBS_USER"`) are escaped for exactly this reason, so they expand when the user *sources* `r_env.sh`, not when it is generated.

By contrast, `templates/r_snapshot.sh` is a **static, path-independent** file: it is copied verbatim into each request's `env_setup/` and reads `$R_LIBS_USER` at run time, so it needs no escaping discipline. Prefer this pattern (static template + copy) over heredoc generation when a helper does not need request-specific paths baked in.

## What the generated `r_env.sh` does

The generated helper is meant to be `source`d (`source env_setup/r_env.sh R/4.4.0`), not executed. It:
1. Loads the given LMOD R module (default `R`), and on success sets `R_LIBS_USER` to a per-module library dir inside the request folder, creating it if needed.
2. Appends a self-contained R activation block (`module load` + `export R_LIBS_USER` + info echoes, between `# >>> R environment ... >>>` / `# <<< ... <<<` markers) to `module_load.sh`, the project's persistent activation script. The write is one heredoc, guarded by the marker so re-sourcing is idempotent (one R block per request). `module_load.sh` is scaffolded with a self-documenting header and is meant to be `source`d.
3. Adds the module's library dir to `.gitignore`.
4. Installs `languageserver` and `vscDebugger` so the request can be worked on in VSCode.
5. Prints next-step instructions for reproducing a researcher's R environment (the manual `scp` target and the `r_snapshot.sh` command).

This depends on the LMOD `module` command being available (BU SCC environment).

## Reproducing a researcher's R environment (`r_snapshot.sh` + renv)

The framework supports reproducing a researcher's R library for debugging and recording a manifest of it. The flow is three steps and **only step 3 is scripted**:

1. `source module_load.sh` — activate the module + `R_LIBS_USER` (this activation script is created by `r_env.sh` during the one-time setup; `r_env.sh` itself is only re-run to rebuild the environment).
2. **The facilitator manually `scp`s** the researcher's library into `R_LIBS_USER`. This is intentionally *not* automated — it requires logging in as the researcher to read their home directory. **No script (or Claude) should attempt this copy.**
3. `bash env_setup/r_snapshot.sh` — runs `renv::snapshot(library = R_LIBS_USER, type = "all")` to write `env_setup/renv.lock`.

Key design points:
- renv is adopted **facilitator-side only** — `renv::snapshot()` records whatever is in the library, so the researcher need never have used renv.
- renv is used to **document, not repopulate**: the goal is debugging their *exact* state, so packages are never reinstalled (which could drift versions and mask the bug).
- renv is installed into a **separate tools library** (`env_setup/.renv-tools/`, gitignored) so it does not appear in the manifest.
- `env_setup/renv.lock` **is tracked** in git (the record of what was reproduced); the reproduced library under `R/<version>/`, `env_setup/r_snapshot.sh`, and `.renv-tools/` are gitignored.
