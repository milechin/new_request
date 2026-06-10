# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`bin/new_request.sh` is a bash script used by an HPC facilitator (Boston University SCC) to scaffold a directory hierarchy for each new researcher support request. There is no build system and no application — the project is a set of bash scripts under `bin/` plus the `templates/` and `.claude/` assets they wire into each workspace, and the generated output. Scripts are organized by language:

- **Common tools (top-level `bin/`):** `new_request.sh` (scaffolder) and `triage_build_log.sh` (general build-log analyzer). Put `bin/` on your `PATH`.
- **Per-language toolsets (`bin/<lang>/`):** e.g. `bin/r/` holds `r_env.sh`, `r_snapshot.sh`, `r_install.sh`; `bin/python/` is a placeholder. These are **activated per request** (see Running) rather than always on `PATH`.
- **`.claude/`** holds commands (`commands/init-request.md`), skills (`skills/triage-build-log/`), and agents (`agents/r-install-debugger.md`), symlinked whole into every workspace.

## Running

```console
new_request.sh CLIENT TICKET [DIR] [--lang r[,python]]    # bin/ on PATH; or: bash bin/new_request.sh ...
```

Creates `${DIR}/${CLIENT}/${TICKET}/` (DIR defaults to `pwd`), populates it with `data/`, `env_setup/`, `scripts/`, `output/`, `context/`, a `.gitignore`, a `module_load.sh` (self-documenting header + home-isolation block), a per-workspace `CLAUDE.md` + `context/` templates (copied from `templates/`), a symlinked `.claude/` (→ this repo's `.claude/`, so all of its commands/skills/agents are available), and runs `git init`. `--lang` records the request's language(s): for each, `new_request.sh` appends `export PATH="<repo>/bin/<lang>:$PATH"` to the workspace `module_load.sh`, so **`source module_load.sh` activates that language's tools**. Exits 1 (and prints `Help`) if CLIENT/TICKET is missing, contains `/` or `..`, or the target exists; `-h`/`--help` exits 0.

## Per-request context (CLAUDE.md, context/, .claude)

Each generated workspace carries its own troubleshooting context:
- **`CLAUDE.md`** (tracked) — per-workspace map of the layout + conventions. Static copy of `templates/CLAUDE.md`.
- **`context/`** (tracked) — `problem.md` + `links.md` for the facilitator; `/init-request` also writes `context/SUMMARY.md`.
- **`.claude/`** — a **symlink** to this repo's own `.claude/`, so every command/skill/agent is available in every workspace and adding a new one needs no re-scaffolding. Organize by language namespace (commands in `commands/<lang>/`, agents/skills `<lang>-` prefixed; truly general ones unprefixed). The workspace `.claude` symlink is gitignored (absolute path into this repo; the `.gitignore` entry is `.claude`, no trailing slash, so it matches the symlink); Claude Code still discovers everything through it.

## Testing

No test framework. `test/inc1234/` is committed sample output (a generated artifact). To verify changes, run into a throwaway dir and inspect; for `triage_build_log.sh`, feed crafted logs and check the classification:

```console
bash bin/new_request.sh testclient testticket /tmp --lang r
```

## Architecture: language toolsets + generated files

Helper scripts are **static** and grouped by language under `bin/<lang>/` (plus common tools at top level); they're maintained once and run against any workspace — not generated or copied per request. A new language is added by creating `bin/<lang>/` and, optionally, `.claude/commands/<lang>/` + `<lang>-`prefixed skills/agents.

`new_request.sh` *generates* two per-workspace files via `cat > ... << EOF` heredocs: `.gitignore` and `module_load.sh`. The `module_load.sh` home-isolation heredoc is the one place escaping is load-bearing:
- **Unescaped** (e.g. `${NEW_DIR}`) — expanded at generation time, baking the workspace's absolute paths in.
- **Escaped `\$`** (e.g. `\$XDG_CACHE_HOME` in the `mkdir` line, `\$PATH` in the `--lang` toolset blocks) — written literally so they expand when the user *sources* `module_load.sh`.

When work doesn't need request-specific paths baked in, prefer a **static script under `bin/`** (resolve the workspace at runtime) over heredoc generation.

## What `bin/r/r_env.sh` does (one-time R setup)

`r_env.sh [R_MODULE] [WORKSPACE]` is **run** (not sourced); it sets up an isolated R environment for the workspace (default `$PWD`):
1. Loads the LMOD R module (default `R`) in its own process; computes a per-module library dir (`R/<module>/`, or `R/default/`) and `mkdir -p`s it.
2. Installs `languageserver` and `vscDebugger` into that library (`lib=`).
3. Adds the module's library dir to the workspace `.gitignore`.
4. Appends a guarded R activation block (`module load` + `export R_LIBS_USER` + info echoes, between `# >>> R environment >>>` / `# <<< <<<` markers) to `module_load.sh` (idempotent).

Activation is separate: **`source module_load.sh`** loads the module, sets `R_LIBS_USER`, puts the request's `bin/<lang>` toolset(s) on `PATH` (from `--lang`), and exports the home-isolation vars `new_request.sh` baked in (`XDG_*`, `RENV_PATHS_ROOT`, `R_ENVIRON_USER`/`R_PROFILE_USER`/`R_HISTFILE`) — keeping caches/config/data/history and the renv cache in the workspace, not `$HOME`. Best-effort (honors XDG / `tools::R_user_dir()`); scripts hardcoding `~`/absolute home paths still escape. Depends on the LMOD `module` command (BU SCC).

## Reproducing a researcher's R environment (`bin/r/r_snapshot.sh` + renv)

Four steps; **the copy (step 3) is manual**:
1. `r_env.sh R/X.Y <workspace>` — one-time setup.
2. `source <workspace>/module_load.sh` — activate.
3. **The facilitator manually `scp`s** the researcher's library into `R_LIBS_USER`. Intentionally *not* automated — it requires logging in as the researcher. **No script (or Claude) should attempt this copy.**
4. `r_snapshot.sh <workspace>` — runs `renv::snapshot(library = R_LIBS_USER, type = "all", force = TRUE)` to write `env_setup/renv.lock`.

Key points: renv is adopted **facilitator-side only** (records whatever's in the library; the researcher need not use renv); used to **document, not repopulate** (debugging their *exact* state — never reinstall); `force = TRUE` bypasses pre-flight validation since a copied library is a partial closure; renv installs into a separate tools lib (`env_setup/.renv-tools/`, gitignored); `env_setup/renv.lock` **is tracked**, the reproduced `R/<version>/` and `.renv-tools/` are gitignored.

## Build-log triage & R-install debugging

- **`bin/triage_build_log.sh [LOG|WORKSPACE]`** — language-agnostic deterministic pre-filter: strips compiler/warning noise, surfaces the real signal + tail, detects the ecosystem, and classifies (SUCCESS / COMPILE-ERROR / LINK-ERROR / OOM-KILL / MISSING-DEPENDENCY / CONFIGURE-ERROR / ENV-NOT-ACTIVATED / UNKNOWN). Always on PATH; usable on any build log.
- **`.claude/skills/triage-build-log/`** — model-invoked skill that runs the pre-filter (keeping huge logs out of context), declares the ecosystems it supports (R, Python, C/C++, Fortran), applies per-ecosystem knowledge packs, and **reports back when a log's language is unsupported** rather than forcing a class.
- **`bin/r/r_install.sh <pkg> [ws]`** — reproduces a researcher's R package install (bare-`source` activate → install → `output/<pkg>_install.log` → present/loads check → triage).
- **`.claude/agents/r-install-debugger.md`** — subagent that infers the package from `context/problem.md`, runs `r_install.sh` in its own context, and returns a short classified verdict (via the triage skill).
