# Benchmarks

Measurement harnesses for the perf question in #1503: whether any of the
SpectrumStrategy 1.0.0 performance work (`Spectrum3847/SpectrumStrategy#1450`)
is worth porting here. They are not tests: nothing here asserts, and
`flutter test` only runs `*_test.dart`, so these never run in CI and cost no
minutes. Run one when a change claims to make something faster, and quote the
before and after in the PR.

```bash
flutter test test/benchmark/pit_cache_bench.dart
flutter test test/benchmark/pit_sync_bench.dart
flutter test test/benchmark/bootstrap_bench.dart
```

Every number comes out of the debug test VM, which is slower than a release
build and does not touch a real disk or a real platform channel. Treat them as
a shape (linear, quadratic, flat) and a ratio between two options, not as a
prediction of milliseconds on a Kindle.

All five pit features (inventory, packing, borrowed, maps, schedule) share
one implementation, `PitControllerMixin`, so a benchmark against one
controller measures the cache and sync cost for all five; `pit_cache_bench`
notes the payload size for each model to show where they diverge.

Baseline figures, and what they say about the app, are in
`agent-docs/decisions/performance-baseline.md`.
