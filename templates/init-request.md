---
description: Build troubleshooting context for this HPC request workspace
---

You are helping an HPC facilitator troubleshoot a researcher's R issue in this request workspace. Build a working understanding of the request and record it.

Do the following, then stop and report:

1. **Structure** — Read `./CLAUDE.md` for the workspace layout.
2. **Problem & links** — Read every file in `./context/` (e.g. `problem.md`, `links.md`, and any other notes the facilitator added). This is the researcher's reported problem and the references you should use. If `links.md` contains URLs that are central to the problem, fetch the key ones.
3. **Scripts** — Inventory `./scripts/`: list the researcher's scripts, identify the language(s), the likely entry point(s), and how they are intended to be run. Note anything that looks related to the reported problem.
4. **Environment** — Read `./module_load.sh` (R module, `R_LIBS_USER`, cache/config isolation) and, if present, `./env_setup/renv.lock` (the reproduced R package versions). Note the R version and any packages likely relevant to the issue.
5. **Write the summary** — Create or update `./context/SUMMARY.md` with these sections:
   - **Problem** — concise statement of the issue (from `context/`).
   - **Environment** — R module/version, key packages, how to activate (`source module_load.sh`).
   - **Scripts** — inventory with entry point(s) and run command(s).
   - **Links / References** — from `context/links.md`.
   - **Open questions** — what's unclear or needs the facilitator's input.

Then give me a short (5–10 line) summary of the request and ask which part to investigate first. Do not start changing the researcher's scripts yet.
