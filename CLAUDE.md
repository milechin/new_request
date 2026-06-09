# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`bin/new_request.sh` is a bash script used by an HPC facilitator (Boston University SCC) to scaffold a directory hierarchy for each new researcher support request. There is no build system, no dependencies to install, and no application — the project is a handful of bash scripts in `bin/` (`new_request.sh`, `r_env.sh`, `r_snapshot.sh`), the `templates/` they copy in, and their generated output. Put `bin/` on your `PATH` to run them from anywhere.

## Running

```console
new_request.sh CLIENT TICKET [DIR]      # bin/ on PATH; or: bash bin/new_request.sh ...
```

Creates `${DIR}/${CLIENT}/${TICKET}/` (DIR defaults to `pwd`), populates it with `data/`, `env_setup/`, `scripts/`, `output/`, `context/`, a `.gitignore`, a `module_load.sh` (self-documenting header + home-isolation block), a per-workspace `CLAUDE.md` + `context/` templates (copied from `templates/`), a symlinked `.claude/commands/init-request.md` (the `/init-request` slash command, pointing back into this repo), and runs `git init` inside it. The R helpers are **not** copied in — they live centrally in this repo's `bin/` (`r_env.sh`, `r_snapshot.sh`) and are run against a workspace (see below). The script exits with status 1 (and prints `Help`) if CLIENT or TICKET is missing, contains `/` or `..`, or if the target directory already exists; `-h`/`--help` prints help and exits 0.

## Per-request context (CLAUDE.md, context/, /init-request)

Each generated workspace carries its own troubleshooting context, from `templates/`:
- **`CLAUDE.md`** (tracked) — a per-workspace map of the directory structure + working conventions, so Claude knows the layout when helping debug. Static copy of `templates/CLAUDE.md`.
- **`context/`** (tracked) — `problem.md` (the issue) and `links.md` (references) for the facilitator to fill in; `/init-request` also writes `context/SUMMARY.md` here.
- **`.claude/commands/init-request.md`** — a **symlink** to `templates/init-request.md` in this repo (so editing the command updates every workspace). The `/init-request` command reads `CLAUDE.md` + `context/` + `scripts/` + the environment and writes `context/SUMMARY.md`. `.claude/` is gitignored in the workspace because the symlink is an absolute path into this repo (don't commit it); Claude Code still discovers the command.

## Testing

There is no test framework. The `test/` directory is committed sample output from a real run (`test/inc1234/`) — it is a generated artifact, not a test suite. To verify changes, run the script into a throwaway directory and inspect the result:

```console
bash bin/new_request.sh testclient testticket /tmp
```

## Architecture: central bin/ scripts vs. generated files

The R helpers are **static scripts in `bin/`** (`bin/r_env.sh`, `bin/r_snapshot.sh`), maintained once and run against any workspace — not generated or copied per request. Put `bin/` on your `PATH` to call them. Both are **executed** (not sourced) and take an optional workspace path argument (default `$PWD`).

`new_request.sh` still *generates* two per-workspace files via `cat > ... << EOF` heredocs: `.gitignore` and `module_load.sh`. The `module_load.sh` home-isolation heredoc is the one place escaping is load-bearing:
- **Unescaped** (e.g. `${NEW_DIR}`) — expanded at generation time, baking the workspace's absolute paths in.
- **Escaped `\$`** (e.g. `\$XDG_CACHE_HOME` in the `mkdir` line) — written literally so they expand when the user *sources* `module_load.sh`.

When the work doesn't need request-specific paths baked in, prefer a **static script in `bin/`** (resolve the workspace at runtime) over heredoc generation — that's exactly why `r_env.sh` was moved out of the heredoc.

## What `bin/r_env.sh` does (one-time R setup)

`r_env.sh [R_MODULE] [WORKSPACE]` is **run** (not sourced); it sets up an isolated R environment for the workspace (default `$PWD`) and does not alter your shell:
1. Loads the given LMOD R module (default `R`) in its own process; computes a per-module library dir (`R/<module>/`, or `R/default/`) inside the workspace and `mkdir -p`s it.
2. Installs `languageserver` and `vscDebugger` into that library (`lib=`), for VSCode.
3. Adds the module's library dir to the workspace `.gitignore`.
4. Appends a self-contained R activation block (`module load` + `export R_LIBS_USER` + info echoes, between `# >>> R environment >>>` / `# <<< <<<` markers) to `module_load.sh`, guarded by the marker so re-running is idempotent (one R block per request).

Activation is separate: **`source module_load.sh`** loads the module, sets `R_LIBS_USER`, and exports the home-isolation vars that `new_request.sh` baked in (`XDG_CACHE_HOME`/`XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME`, `RENV_PATHS_ROOT`, `R_ENVIRON_USER`/`R_PROFILE_USER`/`R_HISTFILE`). That keeps package/tool caches, config, data, history, and the renv cache inside the workspace instead of `$HOME`, and stops R reading the facilitator's personal `~/.Renviron`/`~/.Rprofile`. It is **best-effort** (redirects tools honoring XDG / `tools::R_user_dir()`); scripts that hardcode `~` or absolute home paths still escape — use a container or throwaway user for hard isolation.

These depend on the LMOD `module` command being available (BU SCC environment).

## Reproducing a researcher's R environment (`bin/r_snapshot.sh` + renv)

The flow has four steps; **the copy (step 3) is manual and the rest use the `bin/` scripts**:

1. `r_env.sh R/X.Y <workspace>` — one-time setup (above).
2. `source <workspace>/module_load.sh` — activate the module + `R_LIBS_USER` (now and every future session).
3. **The facilitator manually `scp`s** the researcher's library into `R_LIBS_USER`. Intentionally *not* automated — it requires logging in as the researcher. **No script (or Claude) should attempt this copy.**
4. `r_snapshot.sh <workspace>` — runs `renv::snapshot(library = R_LIBS_USER, type = "all", force = TRUE)` to write `env_setup/renv.lock`.

Key design points:
- renv is adopted **facilitator-side only** — `renv::snapshot()` records whatever is in the library, so the researcher need never have used renv.
- renv is used to **document, not repopulate**: the goal is debugging their *exact* state, so packages are never reinstalled.
- `force = TRUE` bypasses renv's pre-flight validation, since a copied library is typically a partial dependency closure.
- renv is installed into a **separate tools library** (`env_setup/.renv-tools/`, gitignored) so it does not appear in the manifest.
- `env_setup/renv.lock` **is tracked** (the record of what was reproduced); the reproduced library under `R/<version>/` and `.renv-tools/` are gitignored.
