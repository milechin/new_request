---
name: triage-build-log
description: Analyze a build/compile/install log (or a pasted error block) to find the real failure and classify it. Use when a researcher's R/Python/C-C++/Fortran build — install.packages, pip wheel, make/CMake, or configure — failed and you need the actual cause, not the warnings. Supports R, Python, C/C++ (make/CMake/autotools), and Fortran; reports back if the log's language is outside that set.
---

You triage build/compile/install logs: find the REAL error, classify it, and recommend a next step — never report a warning as the cause.

## Ecosystems this skill supports
**R, Python, C/C++ (make/CMake/autotools), and Fortran** — plus generic compiler/linker/out-of-memory errors common to all of them. If a log is from another language/build system, say so (see step 2) rather than guessing.

## Procedure
1. Run the deterministic pre-filter (it keeps huge logs out of context):
   `triage_build_log.sh <log-file-or-workspace>`
   It prints the detected **Ecosystem**, a tentative **Classification**, the failing item, the compiler line, the key signal lines, and the log tail. Base your analysis on that; only open the raw log if you need more context around a specific line.
2. Branch on the detected ecosystem:
   - **Supported** → confirm or *correct* the tentative class using the knowledge pack below, then report the cause + next step.
   - **Generic only** (a clear compiler/linker/OOM error but `Ecosystem: unknown`) → give the generic finding and say it's generic.
   - **Unrecognized / unsupported** (`Ecosystem: unknown` and the errors aren't generic — e.g. Rust/Go/Java/Node/Julia) → **report back to the user**: name the suspected language/tool, state that this skill covers only R, Python, C/C++, and Fortran, and offer just the generic findings (if any). Do **not** force a confident classification.
3. Report concisely: **Classification**, the failing package/target, the 1–3 evidence lines that prove it, and the recommended next step. Keep the raw log out of your reply.

## Classifications
`SUCCESS` · `COMPILE-ERROR` · `LINK-ERROR` · `OOM-KILL` · `MISSING-DEPENDENCY` · `CONFIGURE-ERROR` · `ENV-NOT-ACTIVATED` · `UNKNOWN`

## Knowledge packs
**Generic (always):** `warning:`/`note:` lines are NOT the cause — find the `error:`/`fatal error:`. A log that ends mid-compile with no `error:` and no success marker is the signature of an **OOM kill** (especially memory-capped OnDemand/RStudio Server sessions) → recommend more memory / fewer parallel jobs.

**R:** success marker is `* DONE (<pkg>)`. `Rcpp`/`RcppEigen`/`BH` resolve from the **system** library (`/share/pkg.8/...`); their absence from the workspace `R/<ver>/` is normal, not the failure. `Please first load the R module` = environment not activated (`source module_load.sh`). R doesn't save compile output by default — recommend re-running `install.packages("<pkg>", keep_outputs = TRUE)` and reading the END of `<pkg>.out` (one file per compiled dependency).

**Python:** `Failed building wheel for X` / `subprocess-exited-with-error` wrap the real error printed just below — look for `fatal error: Python.h: No such file` (missing python dev headers / load the module), a compiler failure, or `No matching distribution found` (a resolver/index problem, not a build failure).

**C/C++:** separate the **configure stage** (`configure: error:`, `CMake Error`, `CMAKE_*_COMPILER not set`) from compile/link errors. Missing `-dev` libraries appear as `fatal error: X.h: No such file` or `Package '...' was not found in the pkg-config search path`.

**Fortran:** `Fatal Error: Cannot open module file '....mod'` or a `.mod` "compiled by a different version of GNU Fortran" = a stale/mismatched module or wrong build order; `undefined reference to '__<mod>_MOD_<sub>'` = name-mangling / a missing object at link time.
