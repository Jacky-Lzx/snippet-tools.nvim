# Mirror and navigation optimization — 2026-11-05

This round starts from the already optimized `ab2c3fb` baseline. Configuration,
fixtures and timed protocol remain fixed, and only `session.lua` changes at runtime.

The 100-mirror operation improves from 6.429 to 1.179 ms P50
(5.45×), versus LuaSnip's 12.491 ms in this run.
Choice switching improves from 0.567 to 0.411 ms; the final jump
from 0.359 to 0.273 ms, essentially tied with LuaSnip's
0.272 ms. The absolute choice/jump differences are small. Table expansion and
ordinary configured operations are broadly unchanged from the previous optimization.

Diagnostic 100-mirror point lookups fall from 11,013 to 415, plus 100 indexed overlap
queries. Source/dependency text reads fall from 403 to 205. Queries now visit only
intersecting/touching marks for internal writes, with a full restoration pass for
the active field afterward. Every replica still receives its own buffer edit.

Validation: 35 core/registry assertions, 52 attached-input scenarios and 32 PTY states
pass on both Neovim 0.11.0 and 0.12.6. Real configuration validation passes 29 LaTeX
scenarios, 36 LaTeX PTY states and 21 Markdown PTY states. New cases cover adjacent
empty fields, coincident empty mirrors, nested multiline mirrors, identical-text
choices with different fields, source API edits and cleared root marks.

Runtime commit: `1b5cdcc`. The frozen configuration remains `5e6a89f`; the existing
lockfile changes were preserved. Raw files stay local under the paths listed below.
Protocol and reproduction: [bench/README.md](../README.md).
Interactive chart: `bench/results/20261105-round2-comparison/comparison.html`.


Same current configuration and PTY protocol before/after optimization. No engine settings, fixtures, decorations or update events were relaxed to improve timings.

4 alternating optimized-engine/LuaSnip rounds; 400 isolated and 200 configured samples per case/engine, 20 warmup samples each round, 20 fresh module loads and 1000 lifecycle cycles. Before-only measurements precede optimization and cannot eliminate time-of-day effects. P95 is the primary tail statistic; P99 is descriptive, especially for the smaller configured sample set.

The comparison contains 14,400 successful measured input operations across three series, with zero validation failures. Exact text, selection, mode and the delivered UI frame are checked. These are PTY-to-validated-flush endpoints, not physical display latency.

Measurements (UTC): before 2026-11-04T21:25:00.238414+00:00; after 2026-11-04T21:38:21.640407+00:00.

## Changes

- Use namespace-indexed overlap queries for internal replacement gravity, then restore the active field with a full pass after synchronization.
- Index live extmark IDs by owning session and remove entries when subtrees or sessions are disposed.
- Cache navigation order and invalidate it when field structure changes.
- Reuse synchronized state only when changedtick and current field match; validate root marks first, and invalidate on structural changes or parent resumption.
- Read each dependency group once per update pass instead of rereading the same source for every mirror.

## Equivalent isolated definitions

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| choice_toggle | 0.567 | 0.411 | 0.459 | 0.990 | 0.675 | 0.831 | 1.38× | 400 / 400 / 400 |
| jump_final | 0.359 | 0.273 | 0.272 | 0.567 | 0.311 | 0.352 | 1.32× | 400 / 400 / 400 |
| mirrors_10 | 0.598 | 0.549 | 0.576 | 1.160 | 1.027 | 1.333 | 1.09× | 400 / 400 / 400 |
| mirrors_100 | 6.429 | 1.179 | 12.491 | 6.851 | 1.913 | 13.694 | 5.45× | 400 / 400 / 400 |
| plain_input | 0.280 | 0.282 | 0.301 | 0.300 | 0.301 | 0.329 | 0.99× | 400 / 400 / 400 |
| simple_expand | 0.471 | 0.475 | 0.502 | 0.750 | 0.817 | 0.805 | 0.99× | 400 / 400 / 400 |
| table_10x10 | 1.240 | 1.230 | 3.214 | 1.750 | 1.829 | 4.737 | 1.01× | 400 / 400 / 400 |
| table_2x2 | 0.494 | 0.506 | 0.698 | 0.832 | 0.906 | 1.390 | 0.98× | 400 / 400 / 400 |

## Current Markdown configuration

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bold_accept | 3.988 | 3.816 | 6.803 | 7.999 | 7.627 | 12.307 | 1.05× | 200 / 200 / 200 |
| choice_toggle | 5.200 | 4.955 | 5.636 | 9.271 | 8.815 | 10.870 | 1.05× | 200 / 200 / 200 |
| figure_update_jump | 7.496 | 7.722 | 8.338 | 16.436 | 17.551 | 19.003 | 0.97× | 200 / 200 / 200 |
| link_jump | 4.096 | 3.841 | 4.148 | 8.113 | 8.324 | 9.035 | 1.07× | 200 / 200 / 200 |
| plain_input | 2.129 | 2.284 | 2.272 | 4.537 | 5.268 | 4.319 | 0.93× | 200 / 200 / 200 |
| table_10x10 | 12.590 | 12.283 | 142.215 | 19.316 | 18.028 | 179.145 | 1.02× | 200 / 200 / 200 |
| table_2x2 | 4.599 | 4.572 | 9.880 | 8.599 | 8.793 | 17.117 | 1.01× | 200 / 200 / 200 |
| undo_field_edit | 3.362 | 3.398 | 3.799 | 7.878 | 6.691 | 10.764 | 0.99× | 200 / 200 / 200 |

## Fresh module loading

Milliseconds; smaller is better.

| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| require_ms | 1.031 | 1.062 | 6.053 | 1.071 | 1.274 | 6.684 | 0.97× | 20 / 20 / 20 |
| setup_ms | 0.275 | 0.282 | 0.535 | 0.336 | 0.336 | 0.851 | 0.98× | 20 / 20 / 20 |

## Between-round variability

Ranges of the four per-round UI medians in milliseconds.

| Track / operation | Before | Optimized | LuaSnip |
| --- | ---: | ---: | ---: |
| isolated/choice_toggle | 0.489–0.585 | 0.383–0.445 | 0.428–0.525 |
| isolated/jump_final | 0.311–0.403 | 0.269–0.280 | 0.269–0.277 |
| isolated/mirrors_10 | 0.593–0.600 | 0.535–0.574 | 0.550–0.619 |
| isolated/mirrors_100 | 6.246–6.673 | 1.072–1.464 | 11.832–13.164 |
| isolated/plain_input | 0.278–0.285 | 0.279–0.288 | 0.294–0.309 |
| isolated/simple_expand | 0.466–0.475 | 0.465–0.483 | 0.490–0.514 |
| isolated/table_10x10 | 1.138–1.269 | 1.164–1.260 | 2.984–3.427 |
| isolated/table_2x2 | 0.441–0.510 | 0.453–0.528 | 0.641–0.758 |
| configured/bold_accept | 3.900–4.116 | 3.500–4.189 | 5.891–7.126 |
| configured/choice_toggle | 4.534–5.623 | 4.366–5.536 | 5.243–6.220 |
| configured/figure_update_jump | 5.464–13.107 | 5.349–13.995 | 5.466–13.468 |
| configured/link_jump | 3.565–4.364 | 3.536–4.085 | 3.958–4.224 |
| configured/plain_input | 1.871–2.661 | 1.988–2.651 | 2.034–2.459 |
| configured/table_10x10 | 11.709–14.490 | 11.497–13.583 | 136.765–149.493 |
| configured/table_2x2 | 4.189–4.973 | 4.350–5.039 | 9.423–10.782 |
| configured/undo_field_edit | 2.708–4.662 | 2.863–4.182 | 3.104–4.727 |

## Configured-workload scope

This focused experiment uses a shorter repeated editing sequence than the earlier 250-sample/round report. Table numbers include warmup and preceding-case state, and should not be equated with a fresh-session first expansion or directly compared to the older longer-sequence medians.

Configured checkbox focus differs by route; undo measures a normalized field-edit boundary. Both engines remain loaded in the configured track. Plain input is a control, not a value to subtract from other medians.

## Lifecycle memory

Full-GC Lua heap; RSS includes editor/C/allocator state. The same buffer is reused, with undo/backend bookkeeping retained. Growth alone is not a general leak diagnosis.

| Series | Cycles | Lua KiB | RSS KiB | Extmarks | Buffers |
| --- | ---: | ---: | ---: | ---: | ---: |
| before/snippet-tools | 0 | 1400.3 | 16400 | 0 | 1 |
| before/snippet-tools | 100 | 1441.3 | 16992 | 0 | 1 |
| before/snippet-tools | 500 | 1544.8 | 18944 | 0 | 1 |
| before/snippet-tools | 1000 | 1587.9 | 19184 | 0 | 1 |
| after/snippet-tools | 0 | 1398.7 | 16320 | 0 | 1 |
| after/snippet-tools | 100 | 1426.9 | 16960 | 0 | 1 |
| after/snippet-tools | 500 | 1510.2 | 18864 | 0 | 1 |
| after/snippet-tools | 1000 | 1534.8 | 19008 | 0 | 1 |
| after/luasnip | 0 | 2363.6 | 19376 | 105 | 1 |
| after/luasnip | 100 | 2396.7 | 19968 | 205 | 1 |
| after/luasnip | 500 | 2497.5 | 21552 | 605 | 1 |
| after/luasnip | 1000 | 2568.6 | 21856 | 1105 | 1 |

## Revisions and raw evidence

| Source | Before | After |
| --- | --- | --- |
| plugin | ab2c3fb44b09865a2e76734e7d802ff14d48d6fb | 1b5cdccd509eb0bf4afad0c55c5b9cb6cc90b91f |
| config | 5e6a89fb4fef0ea0849bf255d0e920808ce38173 | 5e6a89fb4fef0ea0849bf255d0e920808ce38173 |
| luasnip | 642b0c595e11608b4c18219e93b88d7637af27bc | 642b0c595e11608b4c18219e93b88d7637af27bc |

Local raw before: `bench/results/20261105-round2-before/results.json`
SHA-256: `14a38c2b4c83d26602ad24546d5d6d53b0dbe6fb44f25f6c87fadba22e4884cc`

Local raw after: `bench/results/20261105-round2-after/results.json`
SHA-256: `9200fa12497c6334b31d1b475380669f698b00108ba475891aaf75561a808794`

Runtime/harness hashes, startup samples, every input sample and round summaries are in those ignored local files. The interactive comparison is generated alongside this report.

## Limits

- The Markdown configuration has changed since the first comparison: TeX snippets have migrated. This run collects a fresh pre-optimization baseline under that same new configuration.
- LuaSnip and optimized-engine rounds alternate, but the baseline-only phase ran earlier; sub-millisecond changes and host-load differences deserve caution.
- This run targets editing. Trigger lookup/collection scaling was not changed or remeasured.
- Profile call counts are instrumented diagnostics, separate from uninstrumented formal timings.
- Each mirror still requires its own buffer replacement. Coincident empty or heavily overlapping ranges can still return many marks from overlap queries.
- No field-selection transport, folding protection, update events or snippet semantics were relaxed. Ordinary sub-millisecond differences remain sensitive to scheduling noise.

## Protocol provenance

The six input/fixture/harness hashes checked by this report match across before/after.

## Instrumented API diagnostics

Median call counts over ten isolated operations after warmup. Diagnostic latency is excluded from the formal comparison.

| Operation / API | Before calls | Optimized calls |
| --- | ---: | ---: |
| table_10x10/nvim_buf_set_extmark | 204 | 204 |
| table_10x10/nvim_buf_get_extmark_by_id | 107 | 107 |
| table_10x10/nvim_buf_get_extmarks | 0 | 0 |
| table_10x10/nvim_buf_get_lines | 18 | 18 |
| table_10x10/nvim_buf_get_text | 0 | 0 |
| table_10x10/nvim_buf_set_text | 1 | 1 |
| mirrors_100/nvim_buf_set_extmark | 401 | 300 |
| mirrors_100/nvim_buf_get_extmark_by_id | 11013 | 415 |
| mirrors_100/nvim_buf_get_extmarks | 0 | 100 |
| mirrors_100/nvim_buf_get_lines | 612 | 414 |
| mirrors_100/nvim_buf_get_text | 403 | 205 |
| mirrors_100/nvim_buf_set_text | 100 | 100 |
| choice_toggle/nvim_buf_set_extmark | 1 | 1 |
| choice_toggle/nvim_buf_get_extmark_by_id | 30 | 19 |
| choice_toggle/nvim_buf_get_extmarks | 0 | 1 |
| choice_toggle/nvim_buf_get_lines | 20 | 16 |
| choice_toggle/nvim_buf_get_text | 8 | 5 |
| choice_toggle/nvim_buf_set_text | 1 | 1 |
| jump_final/nvim_buf_set_extmark | 2 | 2 |
| jump_final/nvim_buf_get_extmark_by_id | 13 | 6 |
| jump_final/nvim_buf_get_extmarks | 0 | 0 |
| jump_final/nvim_buf_get_lines | 9 | 5 |
| jump_final/nvim_buf_get_text | 3 | 0 |
| jump_final/nvim_buf_set_text | 0 | 0 |

Instrumented before: `bench/results/20261105-round2-ranges-before/profile.json`; SHA-256 `f74f2b516f4bbeb9f999f40c61a46124b504b6b94be85713356f609dc9a0a0d1`.

Instrumented optimized: `bench/results/20261105-round2-ranges-final/profile.json`; SHA-256 `0a943e36d7bd7b8ccc8ed2a3b2802b6ce54911a0f094966712f911fb5fd4b20a`.
