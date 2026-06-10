#!/bin/bash -l
#
# triage_build_log.sh -- language-agnostic build-log triage (deterministic pre-filter).
#
# Strips known compiler/warning noise, surfaces the real error signal, detects the
# build ecosystem, and classifies the outcome. Meant to feed the `triage-build-log`
# skill (so huge logs don't flood the model's context), but is useful standalone on
# ANY build/compile/install log.
#
# USAGE
#   triage_build_log.sh [LOG | WORKSPACE]
#     LOG        a build/compile/install log file to analyze.
#     WORKSPACE  a request dir; uses the newest output/*_install.log, else
#                context/problem.md. Default: current directory.
#
# Classes: SUCCESS / COMPILE-ERROR / LINK-ERROR / OOM-KILL / MISSING-DEPENDENCY /
#          CONFIGURE-ERROR / ENV-NOT-ACTIVATED / UNKNOWN
# Exit:    0 on SUCCESS, 1 on a detected failure/unknown, 2 on a usage error.

set -uo pipefail

IN="${1:-$PWD}"
if [ -f "$IN" ]; then
  LOG="$IN"
elif [ -d "$IN" ]; then
  LOG="$(ls -t "$IN"/output/*_install.log 2>/dev/null | head -n1 || true)"
  if [ -z "${LOG:-}" ] && [ -f "$IN/context/problem.md" ]; then
    LOG="$IN/context/problem.md"
  fi
else
  printf 'ERROR: not a file or directory: %s\n' "$IN" >&2
  exit 2
fi
if [ -z "${LOG:-}" ] || [ ! -f "$LOG" ]; then
  printf 'ERROR: no log found. Pass a log file, or a workspace with output/*_install.log or context/problem.md.\n' >&2
  exit 2
fi

has()  { grep -Eqi -- "$1" "$LOG"; }   # case-insensitive presence test
hasc() { grep -Eq  -- "$1" "$LOG"; }   # case-sensitive presence test

# --- ecosystem detection (first match wins) ---
if   hasc '\* installing \*source\* package|R CMD INSTALL|\* DONE \(|/R/library'; then ECO=R
elif has  'building wheel|pyproject\.toml|setup\.py|site-packages|subprocess-exited-with-error|python[0-9.]*\.h'; then ECO=Python
elif hasc 'CMake Error|CMakeLists\.txt|^configure:|checking for '; then ECO=C/C++
elif has  'gfortran|\.f90|\.f95|\.F90|_MOD_|cannot open module file'; then ECO=Fortran
elif hasc 'g\+\+|gcc |cc1plus|clang'; then ECO=C/C++
else ECO=unknown
fi

# --- classification (order = most specific / most critical first) ---
CLASS=UNKNOWN
if   hasc 'Please first load the R module|command not found'; then CLASS=ENV-NOT-ACTIVATED
elif has  'Killed|out of memory|virtual memory exhausted|cannot allocate|std::bad_alloc'; then CLASS=OOM-KILL
elif has  'fatal error: [^ ]*\.h: No such file|python[0-9.]*\.h|was not found in the pkg-config|No package .* found|there is no package called|dependenc.* (is|are) not available|Cannot open module file'; then CLASS=MISSING-DEPENDENCY
elif has  'undefined reference to|cannot find -l|collect2: error: ld returned|DSO missing from command line|multiple definition of|recompile with -fPIC|ld: cannot'; then CLASS=LINK-ERROR
elif hasc 'configure: error:|CMake Error|CMAKE_(C|CXX)_COMPILER not set'; then CLASS=CONFIGURE-ERROR
elif hasc 'error:|fatal error:|^ERROR:|compilation failed for package|had non-zero exit status|Failed building wheel|Could not build wheels|metadata-generation-failed|legacy-install-failure|subprocess-exited-with-error|ModuleNotFoundError|No matching distribution found'; then CLASS=COMPILE-ERROR
elif hasc '\* DONE \(|Successfully installed|Successfully built|Build succeeded|Built target'; then CLASS=SUCCESS
elif hasc 'g\+\+|gcc |cc1plus|clang|gfortran'; then CLASS=OOM-KILL   # compile lines but no error/success marker -> likely truncated (OOM)
fi

# --- failing package / target (best-effort) ---
PKG="$(grep -Eo '(failed for package|installation of package|building wheel for) [^A-Za-z0-9]*[A-Za-z0-9._-]+' "$LOG" 2>/dev/null | head -n1 | grep -Eo '[A-Za-z0-9._-]+$' || true)"

# --- compiler / toolchain line (first invocation) ---
CC_LINE="$(grep -Em1 'g\+\+|gcc |gfortran|clang|cc1plus' "$LOG" 2>/dev/null || true)"

# --- noise vs signal patterns ---
NOISE='\[-W|warning:|note:|ignoring attributes on template argument|__m128d|required from|in instantiation of|recursively required|skipping [0-9]+ instantiation contexts|^trying URL|^\*\* (R|inst|byte-compile|help|building package indices|testing if installed package)|\[[ 0-9]+%\]|^Content type|^downloaded |^=+$'
SIGNAL='error:|fatal error:|^ERROR|undefined reference to|cannot find -l|collect2: error|DSO missing|multiple definition of|recompile with -fPIC|ld: cannot|No such file or directory|pkg-config|No package .* found|Killed|out of memory|virtual memory exhausted|cannot allocate|std::bad_alloc|configure: error:|CMake Error|CMAKE_(C|CXX)_COMPILER|No rule to make target|recipe for target|make(\[[0-9]+\])?: \*\*\*|had non-zero exit status|compilation failed for package|there is no package called|unable to load shared object|cannot open shared object|namespace load failed|Please first load the R module|subprocess-exited-with-error|Failed building wheel|Could not build wheels|metadata-generation-failed|legacy-install-failure|ModuleNotFoundError|ImportError|No matching distribution|Microsoft Visual C\+\+|Cannot open module file|\* DONE \(|Successfully installed|Successfully built'

SIGNAL_LINES="$(grep -Ev -- "$NOISE" "$LOG" 2>/dev/null | grep -E -- "$SIGNAL" 2>/dev/null | head -n 25 || true)"

# --- recommended next step ---
case "$CLASS" in
  ENV-NOT-ACTIVATED)  NEXT="Environment not active: source the workspace module_load.sh (and load the right module) so the compiler/R is on PATH, then re-run.";;
  OOM-KILL)           NEXT="Out-of-memory during compile, or the log was truncated mid-build. Re-run with more RAM / a larger job and avoid heavy parallel 'make -j'; capped OnDemand/RStudio sessions are a common cause.";;
  MISSING-DEPENDENCY) NEXT="A required header/library/package is missing. Install the -dev package or load the module that provides it (see the 'No such file'/pkg-config line), then re-run.";;
  LINK-ERROR)         NEXT="Link-time failure: a needed library is missing or out of order. Add the right -l/-L (or load the module providing the .so), then re-run.";;
  CONFIGURE-ERROR)    NEXT="configure/CMake failed before compiling. Resolve the reported missing tool/dependency/compiler, then re-run.";;
  COMPILE-ERROR)      NEXT="Genuine compile error. Read the 'error:' line(s) below; for R re-run with install.packages(..., keep_outputs=TRUE) and read the END of <pkg>.out; for Python read the full pip build output.";;
  SUCCESS)            NEXT="Build succeeded.";;
  *)                  NEXT="No known error signature matched. Inspect the tail below, or pass the specific build log.";;
esac

# --- report ---
printf '=== build-log triage ===\n'
printf 'Log:            %s\n' "$LOG"
printf 'Ecosystem:      %s\n' "$ECO"
printf 'Classification: %s\n' "$CLASS"
[ -n "${PKG:-}" ]     && printf 'Failing item:   %s\n' "$PKG"
[ -n "${CC_LINE:-}" ] && printf 'Compiler:       %s\n' "$CC_LINE"
printf '\n--- key signal lines ---\n%s\n' "${SIGNAL_LINES:-(none matched)}"
printf '\n--- log tail (last 15 lines) ---\n'
tail -n 15 "$LOG"
printf '\nRecommended next step: %s\n' "$NEXT"

[ "$CLASS" = SUCCESS ] && exit 0 || exit 1
