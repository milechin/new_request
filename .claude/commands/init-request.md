---
description: Build troubleshooting context for this HPC request workspace
---

You are helping an HPC facilitator troubleshoot a researcher's issue in this request workspace. Build a working understanding of the request and record it.

Do the following, then stop and report:

1. **Structure** — Read `./CLAUDE.md` for the workspace layout.
2. **Problem & links** — Read the context files in `./context/` (`problem.md`, `links.md`, and any other notes the facilitator added) — but **not** the contents of `./context/logs/`, which is handled in step 4. This is the researcher's reported problem and the references to use; if `links.md` has URLs central to the problem, fetch the key ones.
3. **Scripts** — Inventory `./scripts/`: list the researcher's scripts, identify the language(s), the likely entry point(s), and how they are intended to be run. Note anything related to the reported problem.
4. **Logs** — Look in `./context/logs/` for facilitator-uploaded build/job logs. **Do not read whole logs — they can be huge** (multi-MB logs are common). For each file, sample the **head and tail** (e.g. `head -n 40 <log>` and `tail -n 40 <log>`) to identify what it is (build/compile/install vs. job/run output). For anything that looks like a **build/compile/install log you MUST triage it — never hand-`grep`/`cat` it.** Resolve the triage tool from this workspace's `.claude` symlink (which points into the tooling repo) so it works regardless of PATH:
   ```
   TRIAGE="$(dirname "$(readlink -f .claude)")/bin/triage_build_log.sh"
   "$TRIAGE" context/logs/<log>
   ```
   (or invoke the `triage-build-log` skill, which does the same). Record each log's classification + key finding. If the triage shows an **R package install failure**, recommend the **`r-install-debugger`** agent as the next step (don't run it yourself here).
5. **Environment** — Read `./module_load.sh` (modules, `R_LIBS_USER`, toolset PATH, cache/config isolation) and, if present, `./env_setup/renv.lock` (reproduced R package versions). Note the version(s) and any packages relevant to the issue.
6. **Write the summary** — Create or update `./context/SUMMARY.md` with these sections:
   - **Problem** — concise statement of the issue (from `context/`).
   - **Environment** — module/version, key packages, how to activate (`source module_load.sh`).
   - **Scripts** — inventory with entry point(s) and run command(s).
   - **Logs** — for each log in `context/logs/`: what it is, and the triage classification / key finding (not the raw log).
   - **Links / References** — from `context/links.md`.
   - **Open questions** — what's unclear or needs the facilitator's input.

Then give me a short (5–10 line) summary of the request and ask which part to investigate first. Do not start changing the researcher's scripts yet.
