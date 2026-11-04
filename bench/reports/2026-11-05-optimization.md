# Editing optimization — 2026-11-05

The targeted hotspots improved substantially in this local run. For equivalent
isolated definitions, the 10×10 table goes from 16.561 to 1.235 ms P50 (13.41×),
and 100 mirrors from 22.614 to 6.666 ms (3.39×). LuaSnip measures 3.272 and
12.176 ms respectively under the same fixture and event policies.

Simple expansion is effectively unchanged. LuaSnip retains a small advantage for
choice switching and the final jump. The current configuration's 10×10 table goes
from 30.347 to 12.586 ms, versus LuaSnip's 144.582 ms, with the shorter repeated
workload described below. These configured timings include integration/state costs.

Validation: 35 core/registry assertions, 46 attached-input scenarios, 32 engine PTY
states, 29 real-config LaTeX scenarios, 36 LaTeX PTY states, 21 Markdown PTY states,
and six measurement-protocol checks pass. The two added engine regressions edit
100 independent fields and 30 multiline UTF-8 fields with indentation.

Runtime optimization: `8896a67`. The benchmark-only exit/cache-race fix is
`21d6356`. Configuration remains at `5e6a89f`, including its pre-existing lockfile
working-tree changes. No configuration change was made for this optimization.

Protocol and reproduction: [bench/README.md](../README.md).
The interactive chart is local at
`bench/results/20261105-editing-comparison/comparison.html`.


Same current configuration and PTY protocol before/after optimization. No engine settings, fixtures, decorations or update events were relaxed to improve timings.

4 alternating optimized-engine/LuaSnip rounds; 400 isolated and 200 configured samples per case/engine, 20 warmup samples each round, 20 fresh module loads and 1000 lifecycle cycles. Before-only measurements precede optimization and cannot eliminate time-of-day effects. P95 is the primary tail statistic; P99 is descriptive, especially for the smaller configured sample set.

The comparison contains 14,400 successful measured input operations across three series, with zero validation failures. Exact text, selection, mode and the delivered UI frame are checked. These are PTY-to-validated-flush endpoints, not physical display latency.

Measurements (UTC): before 2026-11-04T21:00:49.456163+00:00; after 2026-11-04T21:15:02.579167+00:00.

## Changes

- Index line starts once per rendered model instead of rescanning prefixes for every node coordinate.
- Copy numeric navigation paths directly instead of using general recursive table copies.
- Track editable/computed records; literal text uses its enclosing field/root instead of its own extmark.
- Reuse synchronous-pass buffer bounds/line reads and avoid rewriting unchanged extmark gravity/highlights.
- Read initial field values from the just-inserted model instead of querying them back through the buffer.

## Equivalent isolated definitions

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| choice_toggle | 0.570 | 0.583 | 0.440 | 1.071 | 0.976 | 0.689 | 0.98× | 400 / 400 / 400 |
| jump_final | 0.367 | 0.358 | 0.269 | 0.553 | 0.504 | 0.336 | 1.03× | 400 / 400 / 400 |
| mirrors_10 | 0.736 | 0.620 | 0.550 | 1.291 | 1.104 | 1.298 | 1.19× | 400 / 400 / 400 |
| mirrors_100 | 22.614 | 6.666 | 12.176 | 24.165 | 7.219 | 13.541 | 3.39× | 400 / 400 / 400 |
| plain_input | 0.279 | 0.283 | 0.300 | 0.301 | 0.308 | 0.325 | 0.99× | 400 / 400 / 400 |
| simple_expand | 0.483 | 0.480 | 0.479 | 0.837 | 0.848 | 0.826 | 1.00× | 400 / 400 / 400 |
| table_10x10 | 16.561 | 1.235 | 3.272 | 17.556 | 1.758 | 4.398 | 13.41× | 400 / 400 / 400 |
| table_2x2 | 0.560 | 0.505 | 0.652 | 1.047 | 0.893 | 1.283 | 1.11× | 400 / 400 / 400 |

## Current Markdown configuration

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bold_accept | 3.951 | 4.006 | 6.474 | 7.782 | 9.052 | 13.783 | 0.99× | 200 / 200 / 200 |
| choice_toggle | 5.047 | 5.335 | 6.093 | 8.983 | 9.775 | 13.021 | 0.95× | 200 / 200 / 200 |
| figure_update_jump | 8.464 | 7.632 | 8.442 | 16.836 | 16.595 | 20.411 | 1.11× | 200 / 200 / 200 |
| link_jump | 3.845 | 4.196 | 4.114 | 7.714 | 8.726 | 9.576 | 0.92× | 200 / 200 / 200 |
| plain_input | 2.191 | 2.248 | 2.149 | 4.572 | 4.391 | 5.204 | 0.98× | 200 / 200 / 200 |
| table_10x10 | 30.347 | 12.586 | 144.582 | 36.505 | 18.220 | 178.412 | 2.41× | 200 / 200 / 200 |
| table_2x2 | 4.740 | 4.532 | 9.826 | 8.088 | 8.403 | 17.486 | 1.05× | 200 / 200 / 200 |
| undo_field_edit | 3.559 | 3.329 | 3.684 | 9.775 | 8.444 | 9.703 | 1.07× | 200 / 200 / 200 |

## Fresh module loading

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| require_ms | 1.182 | 1.031 | 5.894 | 1.405 | 1.136 | 6.419 | 1.15× | 20 / 20 / 20 |
| setup_ms | 0.319 | 0.286 | 0.523 | 0.363 | 0.378 | 0.594 | 1.11× | 20 / 20 / 20 |

## Between-round variability

Ranges of the four per-round UI medians in milliseconds.

| Track / operation | Before | Optimized | LuaSnip |
| --- | ---: | ---: | ---: |
| isolated/choice_toggle | 0.494–0.591 | 0.495–0.643 | 0.430–0.473 |
| isolated/jump_final | 0.313–0.425 | 0.307–0.415 | 0.264–0.272 |
| isolated/mirrors_10 | 0.719–0.762 | 0.588–0.651 | 0.540–0.558 |
| isolated/mirrors_100 | 22.287–23.502 | 6.466–7.035 | 11.915–12.715 |
| isolated/plain_input | 0.264–0.286 | 0.272–0.287 | 0.294–0.306 |
| isolated/simple_expand | 0.471–0.498 | 0.465–0.512 | 0.475–0.482 |
| isolated/table_10x10 | 16.124–16.856 | 1.133–1.276 | 3.086–3.493 |
| isolated/table_2x2 | 0.512–0.575 | 0.446–0.540 | 0.609–0.680 |
| configured/bold_accept | 3.435–4.691 | 3.505–4.818 | 5.846–7.335 |
| configured/choice_toggle | 4.473–5.781 | 4.614–6.223 | 5.411–6.431 |
| configured/figure_update_jump | 5.423–12.904 | 5.299–14.152 | 5.867–12.934 |
| configured/link_jump | 3.744–3.991 | 3.664–4.710 | 3.931–4.395 |
| configured/plain_input | 1.827–2.384 | 1.785–2.630 | 1.834–2.371 |
| configured/table_10x10 | 29.590–31.497 | 11.855–13.527 | 136.087–146.803 |
| configured/table_2x2 | 4.139–5.056 | 4.053–4.792 | 8.996–10.566 |
| configured/undo_field_edit | 2.910–5.121 | 2.775–4.215 | 3.143–5.043 |

## Configured-workload scope

This focused experiment uses a shorter repeated editing sequence than the earlier 250-sample/round report. Table numbers include warmup and preceding-case state, and should not be equated with a fresh-session first expansion or directly compared to the older longer-sequence medians.

Configured checkbox focus differs by route; undo measures a normalized field-edit boundary. Both engines remain loaded in the configured track. Plain input is a control, not a value to subtract from other medians.

## Lifecycle memory

Full-GC Lua heap; RSS includes editor/C/allocator state. The same buffer is reused, with undo/backend bookkeeping retained. Growth alone is not a general leak diagnosis.

| Series | Cycles | Lua KiB | RSS KiB | Extmarks | Buffers |
| --- | ---: | ---: | ---: | ---: | ---: |
| before/snippet-tools | 0 | 1504.2 | 16608 | 0 | 1 |
| before/snippet-tools | 100 | 1531.4 | 17232 | 0 | 1 |
| before/snippet-tools | 500 | 1586.6 | 19104 | 0 | 1 |
| before/snippet-tools | 1000 | 1632.6 | 19216 | 0 | 1 |
| after/snippet-tools | 0 | 1433.9 | 16448 | 0 | 1 |
| after/snippet-tools | 100 | 1471.1 | 17072 | 0 | 1 |
| after/snippet-tools | 500 | 1549.0 | 19072 | 0 | 1 |
| after/snippet-tools | 1000 | 1568.1 | 19104 | 0 | 1 |
| after/luasnip | 0 | 2469.4 | 19728 | 105 | 1 |
| after/luasnip | 100 | 2500.4 | 20304 | 205 | 1 |
| after/luasnip | 500 | 2599.9 | 21936 | 605 | 1 |
| after/luasnip | 1000 | 2669.1 | 22208 | 1105 | 1 |

## Revisions and raw evidence

| Source | Before | After |
| --- | --- | --- |
| plugin | 2ec4fbb2512964a98a13aa46485d93912a69dd4e | 21d6356437b4cc12128b76a0ce5fbd0a39b87536 |
| config | 5e6a89fb4fef0ea0849bf255d0e920808ce38173 | 5e6a89fb4fef0ea0849bf255d0e920808ce38173 |
| luasnip | 642b0c595e11608b4c18219e93b88d7637af27bc | 642b0c595e11608b4c18219e93b88d7637af27bc |

Local raw before: `bench/results/20261105-editing-before/results.json`
SHA-256: `fe1d01c6991c379d57564b4f777020c2d0d28e277c7a0c8fa63d9fdcdb2301e1`

Local raw after: `bench/results/20261105-editing-after/results.json`
SHA-256: `658be24dbfab44971a61ed04d32819f832700651de90453a87fa484edd4052a2`

Runtime/harness hashes, startup samples, every input sample and round summaries are in those ignored local files. The interactive comparison is generated alongside this report.

## Limits

- The Markdown configuration has changed since the first comparison: TeX snippets have migrated. This run collects a fresh pre-optimization baseline under that same new configuration.
- LuaSnip and optimized-engine rounds alternate, but the baseline-only phase ran earlier; sub-millisecond changes and host-load differences deserve caution.
- This run targets editing. Trigger lookup/collection scaling was not changed or remeasured.
- Mirror edits still perform one buffer replacement per replica and scan geometry across records. Extmark writes are reduced, but extremely large mirror sets can still expose quadratic geometry work.
- Profile call counts are instrumented diagnostics, separate from uninstrumented formal timings.

## Protocol provenance

The six input/fixture/harness hashes checked by this report match across before/after.

A prior final-attempt run stopped after an ENOTEMPTY bytecode-cache cleanup race outside timed operations. It is retained under `bench/results/20261105-editing-after-cleanup-interrupted`. Commit `21d6356` makes the editor quit before cache cleanup, with a bounded cleanup retry. The final comparison was restarted; none of that interrupted attempt's samples are pooled.

## Instrumented API diagnostics

Median call counts over ten isolated operations after warmup. Diagnostic latency is excluded from the formal comparison.

| Operation / API | Before calls | Optimized calls |
| --- | ---: | ---: |
| table_10x10/nvim_buf_set_extmark | 668 | 204 |
| table_10x10/nvim_buf_get_extmark_by_id | 542 | 107 |
| table_10x10/nvim_buf_get_lines | 561 | 18 |
| table_10x10/nvim_buf_get_text | 204 | 0 |
| table_10x10/nvim_buf_set_text | 1 | 1 |
| mirrors_100/nvim_buf_set_extmark | 20603 | 401 |
| mirrors_100/nvim_buf_get_extmark_by_id | 21113 | 11013 |
| mirrors_100/nvim_buf_get_lines | 21115 | 612 |
| mirrors_100/nvim_buf_get_text | 403 | 403 |
| mirrors_100/nvim_buf_set_text | 100 | 100 |

Instrumented before: `bench/results/20261105-profile-before/profile.json`; SHA-256 `4a167e449ec0b63fb84c5b9b693f8122990ad5c3df57167cfff038043c8ab786`.

Instrumented optimized: `bench/results/20261105-profile-optimized/profile.json`; SHA-256 `b75c6ce7e7ae0aa5db5d5dd2d4537f99c7ac64d52425e5ace63822545683d41f`.
