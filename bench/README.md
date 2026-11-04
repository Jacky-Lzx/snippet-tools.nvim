# LuaSnip / snippet-tools performance comparison

Run from this plugin checkout, using a real LuaSnip checkout:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 bench/compare.py \
  --luasnip ~/.local/share/nvim/lazy/LuaSnip \
  --config-root ~/.config/nvim \
  --output bench/results/local
python3 bench/report.py bench/results/local/results.json
```

Python 3.9+, Neovim, a POSIX PTY, local Unix sockets and `ps` are required. No
Python packages or benchmark servers are needed. The **configured** track expects
the user's `integrations.snippets` dispatcher and test setup; use `--mode isolated`
on other configurations. Run outside a socket-restricted sandbox: a failed socket
or terminal handshake invalidates input measurements. Only benchmark Neovim child
processes are modified. The live editor and configuration files are untouched.

Defaults: 20 fresh-process loads per engine; 4 alternating engine-order rounds;
250 measured + 50 warmup input samples per case per round; 200 batches for core
matching; 1,000 lifecycle cycles after at least 100 warmup cycles. The seed and
all raw samples are recorded. Full defaults can take tens of minutes with a slow
configured large-table case; use the small validation command below for a smoke run.
Nearest-rank P95/P99 and the arithmetic median are
reported. Inspect per-round summaries instead of treating tiny timing differences
as a stable engine advantage. Four rounds provide four registration/index samples;
their upper quantiles are descriptive, not well-estimated tails.

## Tracks

**Fresh process:** time `require()` and setup inside Neovim, then perform full GC
to measure retained Lua heap above a process-local baseline. This is a fresh Lua
module load with warm OS filesystem caches and a fresh bytecode cache directory;
it is not a reboot/cold-disk test or total application startup measurement.

**Core scaling:** build equivalent literal or Lua-pattern collections of
100/1,000/5,000 definitions, separating registration, first lookup/index construction
and warm matching. Lines vary within timed batches to avoid loop-invariant matching.
After 30 warmup calls, batches are calibrated to at most ten calls (about 0.1ms
target); slow cases use one call. Each sample is divided by its recorded batch size.
LuaSnip's pinned internal `snippet_collection.match_snippet()` is compared with the
new registry; context acquisition, rendering and UI are excluded. The internal
API and both revision hashes are recorded. Native `collection_heap` is before its
lazy index and `indexed_heap` is after first lookup: compare the latter for loaded
collection memory.

**Isolated PTY input:** load only the selected engine. Both use equivalent Lua
definitions, editable choices, immediate mirror updates, no custom decorations
and no finished-snippet history. Cases include simple expansion, 2×2/10×10 dynamic
tables, final navigation, editable choices and 10/100 mirrors. A semantic fixture
is shared; generated buffer text, mode and selected text must match. Builtin
mirrors in snippet-tools correspond to LuaSnip function-node mirrors.

**Configured PTY input:** load the real user configuration and actual sibling
plugin checkouts, then switch buffer-local routing. Both engines remain loaded;
this measures the current integration's total path, including the compatibility
provider, decoration choices, folding, menus and redraws. Lazy definitions are
loaded for the route before timing; empty sources cannot pass preparation. External
LSP processes are disabled by the configuration's existing test setup and sources
are restricted to snippets. This is not an attribution of all latency to an engine.

The original LuaSnip checkbox retains trailing whitespace and enters Insert mode
after selecting `[x]`; the migrated definition selects `[x]`. That configured
case validates each route's native behavior and is not a strictly identical focus
comparison. The isolated choice fixture uses editable alternatives on both engines.
Undo tests normalize the boundary before a field edit and measure undoing that edit,
not differences in completion-acceptance undo grouping.

## Endpoints and correctness

The controller sends actual terminal bytes: an F10 timestamp sentinel, the user
operation and an F12 barrier. The editor then checks exact buffer text, mode and
selection. Pending snippet selection must finish. Dependent updates may complete
through the real event loop; verification retries use zero-delay callbacks rather
than a 15ms file/timer poll.

- `state_ms`: editor F10 handler to validated state after the F12 barrier. Includes
  sentinel dispatch and real scheduled work; it is not a synchronous API microbenchmark.
- `ui_ms`: PTY write to socket receipt of the first Neovim UI flush after validation.
  A real native TUI remains attached; a second line-grid UI supplies frame events.
  Visible text is checked as well as editor state. Receipt is timestamped before
  MessagePack decoding. The final redraw is explicitly requested on both engines.

These endpoints include harness/transport/redraw costs and do not measure physical
display painting. `plain_input` is the control for the same path; its isolated trigger collection is empty. Do not subtract
two medians and call the result precise engine CPU time. Terminal DSR/OSC queries
are answered (including status DSR); E1568 timeouts reject a run.

A failed sample stops that case, is preserved in raw JSON and makes the run fail.
Incorrect fast paths are never counted as successful samples. Preparation and
buffer reset occur outside the measured interval. The same buffer is reused within
each track/round; backend bookkeeping and undo history remain. Inspect within-case
drift as well as round medians: repeated-workload latency need not equal a fresh
session's first expansion. File IO records final results,
never acts as the timed completion signal.

## Lifecycle memory

The isolated memory track repeatedly expands, visits the final stop and clears
the same buffer through real input. Checkpoints report full-GC Lua heap, RSS of
the **editor process** (not its TUI frontend), live buffer extmarks, autocommands
and buffer count. RSS includes allocators and Neovim/C state; Lua heap alone does
not cover every allocation. Growth in a bounded workload is evidence to investigate,
not by itself proof of a general memory leak. Undo history and backend bookkeeping
are not globally purged to manufacture a flat result.

## Quick validation

```sh
PYTHONDONTWRITEBYTECODE=1 python3 bench/test_protocol.py
PYTHONDONTWRITEBYTECODE=1 python3 bench/compare.py \
  --samples 3 --warmup 2 --rounds 1 --startup-runs 1 \
  --core-samples 3 --memory-cycles 10 --output /tmp/snippet-bench-check
stylua --check bench
```

Interrupted runs can be continued with the same command plus `--resume`. Input
protocol hashes and source revisions must match; keep source trees (including
uncommitted runtime changes) and the Neovim executable unchanged. A changed core harness discards
both engines' previous core samples and records that recalibration.

Results under `bench/results/` are ignored by Git. Keep raw `results.json` with
the generated report; it contains hardware/load metadata, arguments, source
revisions, harness file hashes, per-round samples and failure diagnostics.

## Local measurement

[2026-11-05 results](reports/2026-11-05.md) include correctness counts, P50/P95/P99,
round variability, repeated-table drift, memory checkpoints and run provenance.

## Editing optimization experiment

`editing.py` reuses the exact PTY fixtures, state validation and UI-flush endpoints
from `compare.py`, and skips the unrelated collection-scaling microbenchmarks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 bench/editing.py --engines snippet-tools \
  --output bench/results/editing-before
# Apply and validate a runtime change, keeping configuration and fixtures fixed.
PYTHONDONTWRITEBYTECODE=1 python3 bench/editing.py \
  --output bench/results/editing-after
```

Defaults are four alternating rounds, 100 isolated and 50 configured samples per
case per round, 20 warmup samples, 20 fresh module loads, and 1,000 lifecycle
cycles per engine. P95 is the primary tail statistic; P99 at 200 configured
samples is descriptive. Runtime file hashes distinguish pre-change and post-change
sources even when working trees are dirty. Keep the input protocol and configuration
unchanged between phases. The before-only run cannot eliminate time-of-day effects;
compare the concurrently alternated optimized-engine and LuaSnip rounds as well.

`--profile --output <directory>` records API call counts and instrumented times for
10×10 expansion and 100-mirror updates after warmup. These diagnostic times include
instrumentation overhead and are excluded from the formal latency comparison.
