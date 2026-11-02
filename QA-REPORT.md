# Code Audit Report — `Files` (FilesKit + `files` CLI) v1.6.0

Audit date: 2026-10-31 · Commit: `1947d51` · Thoroughness: Standard, plus empirical reproduction of every High/Critical finding.

**Status update:** all Critical and High findings are fixed in the working tree (not yet committed), plus Q1 and P2 along the way. Each fix is marked **Fixed** below. Regression tests are in `Tests/FilesKit/`: `ConfigPrecedenceTests`, `ScanIgnoreTests`, `FuzzyPairTests`, `CopySafetyTests`, `CLIOutputTests` (158 tests, all passing).

Legend: ✅ **Verified** = reproduced against the built binary (scripts in the Appendix). 🔍 **Code review** = found by reading the code, not reproduced.

## Executive Summary

**Overall health: 6 / 10 (C+).** The structure is clean: a library/CLI split, Swift 6 language mode, Result-based APIs, one pinned dependency, and 128 fast passing tests. But this tool's job is to move and delete files, and several paths silently do the wrong thing with user data. The worst bugs are in the CLI option handling, which has no tests at all.

| Severity | Count |
|---|---|
| 🔴 Critical | 2 |
| 🟠 High | 9 |
| 🟡 Medium | 15 |
| ⚪ Low | 12 |

**Top 3 priorities**
1. **Make CLI flags actually override `.files`, and stop honoring destructive settings from configs inside data directories** (C1, C2). Right now a `.files` file in the *source* folder can turn off `--dry-run` and turn on `deletions`.
2. **Make updates atomic and preserve metadata** (H1, H4). An update currently deletes the destination before copying. Files ≥10 MB lose their permissions and mtime.
3. **Fix directory ignore patterns, and move diagnostics to stderr** (H2, H3). Both are quick fixes. Together they fix `node_modules/`-style ignores and the documented `compare --format json > snapshot.json` workflow.

---

## Findings by Category

### 1. Architecture & Design

**Strengths:** Clear `FilesKit` (library) / `files` (CLI) separation. Typed `Result<_, Error>` returns. `AsyncStream<OperationResult>` progress model. Strict Swift 6 concurrency. A single dependency (`swift-argument-parser` 1.6.2, pinned).

#### 🟠 High
- **A1. `DirectoryDifference` cannot represent fuzzy matches.** **Fixed:** it now carries `matches` (left → right path), which is encoded in snapshots and optional on decode. `compare -v` shows "(matched with: …)". `DirectoryDifference.swift:4-11` stores four `Set<String>` of *left*-relative names. When `left/notes1.txt` fuzzy-matches `right/notes2.txt`, the right-hand name is thrown away (`:305-311`).
  - Impact: this lossy model is the root cause of H6. It is also why a fuzzy "update" really creates a new file next to the old one (the README even documents this at `README.md:338-340`).
  - Recommendation: add a pair type (`matched: [MatchedPair(left:right:)]`) and plan operations from it.
  - Effort: 2–3 days (public API change).

#### 🟡 Medium
- **A2. Option resolution is copy-pasted into three commands.** See `CompareCommand.swift:58-74`, `CopyCommand.swift:63-80`, `SyncCommand.swift:85-109`. That is why the C1 precedence bug exists three times.
  - Recommendation: one `ResolvedOptions.resolve(cli:config:)` function with a single precedence rule, unit-tested.
  - Effort: 0.5 day.
- **A3. The three comparison strategies share no core.** `fullComparison` / `optimizedComparison` / `leafFoldersComparison` each reimplement the exact-vs-fuzzy classification (`DirectoryDifference.swift:257-517`). They have already drifted apart (see H5a).
  - Recommendation: one strategy decides *which right files to consider*, and one shared `classify(left:right:)` does the rest.
  - Effort: 1 day.
- **A4. Two-way sync keeps no baseline or state.** Without a record of the last sync, a deletion on one side can't propagate: the file comes back from the other side. When both copies have the same mtime, the conflict is skipped silently (`DirectorySync.swift:407-409`).
  - Recommendation: document the limitation now. Long term, keep a state file (path → hash/mtime at the last sync).
  - Effort: >5 days.

### 2. Code Quality

#### 🔴 Critical
- **C1. `.files` overrides CLI flags, the opposite of what's documented.** ✅ Verified (repro B). **Fixed:** all config-backed flags are now `Bool?` with `--no-` inversions (`--ignore/--no-ignore` replaces the plain `--no-ignore`), resolved as `cli ?? config ?? default`.
  - Where: `SyncCommand.swift:90,95-101,104`, `CopyCommand.swift:68-72,75`, `CompareCommand.swift:63-66,69`. Each uses `config.x ?? cliFlag`. Bool flags with defaults can't tell "not passed" from `false`, so the config always wins. Same for `--format`.
  - Impact: with `dryRun = false` in a `.files`, **`files sync a b --dry-run` performs a real sync.** It also contradicts `README.md:124` and every command's help text ("CLI flags override .files settings").
  - Recommendation: declare the flags as `Bool?` with `inversion: .prefixedNo` (ArgumentParser supports optional Bool flags with inversion). Then resolve as `cli ?? config ?? default`.
  - Effort: 2–3 h including tests.

#### 🟠 High
- **H2. Directory-only ignore patterns (`node_modules/`, `.git/`, `__pycache__/`…) never match.** ✅ Verified (repro A). **Fixed:** scans check each directory with `isDirectory: true` and skip ignored ones entirely, as `.gitignore` does. This also fixes P2.
  - Where: the scanners always call `shouldIgnore(path, isDirectory: false)` (`DirectoryDifference.swift:656,719`), and `Ignore.swift:130-132` rejects directory-only patterns for anything that isn't a directory.
  - Impact: every `dir/` line in `.filesignore.example` and in the README example (`README.md:80`) does nothing. The tests only call `shouldIgnore("node_modules", isDirectory: true)` directly (`IgnorePatternsTests.swift:31,124`) and never go through a scan.
  - Recommendation: test each ancestor directory of the path with `isDirectory: true`. Better: prune during enumeration (see P2).
  - Effort: 2–4 h.
- **H5. Fuzzy matching silently skips files.** All four parts below end with a file that should be synced being treated as "common". **Fixed:** (a) and (c). For (b), basename matching across folders stays, because the README documents it, but ties now go to the same folder. (d) is the documented purpose of `--size-tolerance`, so it is unchanged.
  - a) ✅ In optimized (`cp` / one-way) mode the right side is scanned with an **empty `Ignore()` and `recursive: true`**, ignoring the caller's settings (`DirectoryDifference.swift:349-350`). In repro F, `report1.txt` isn't copied because it "matched" an *ignored* `report2.txt`. In repro M, under `--no-recursive` it matched `sub/report2.txt`.
  - b) 🔍 Matching compares basenames only (`:949,958`), so `a/x.txt` can pair with `z/y/x.txt` in an unrelated folder.
  - c) ✅ **The result is non-deterministic.** Matching is greedy, first come first served, over `Set` iteration order, which Swift randomizes per process (`:948-978`). In repro I, the same input gave two different results across 20 runs (6 vs 14).
  - d) 🔍 With `sizeTolerance > 0`, file contents are never compared (`:296-302`). Two different files with similar names and sizes count as identical and are skipped.
  - Recommendation: pass `ignore`/`recursive` through. Match only within the same parent directory, or make cross-directory matching opt-in. Score all pairs, sort by (similarity desc, path asc), then assign. Keep a content check (or at least a hash of the first and last chunks) when `sizeTolerance > 0`.
  - Effort: 1 day.
- **H6. Two-way sync combined with fuzzy matching aborts, and the failure is hidden in dry-run.** ✅ Verified (repros G, G2). **Fixed:** conflicts are resolved between the matched pair, and the losing file is overwritten in place. Dry-run now lists failures and exits 1.
  - Where: `resolveModifiedFiles` builds the right-hand path from the *left* name (`DirectorySync.swift:341-347`). For fuzzy pairs that file doesn't exist, so `attributesOfItem` throws and planning fails for the whole sync: "Planning failed … notes1.txt no such file", 0 operations.
  - Dry-run: the same failure prints "Would perform 1 operation(s)" with nothing listed and **exits 0**. Failures are only printed and only change the exit code when not in dry-run (`OutputFormatter.swift:108`, `SyncCommand.swift:158`, `CopyCommand.swift:124`), and `.compare` operations are left out of the grouped lists (`OutputFormatter.swift:303-308`).
  - Recommendation: short term, reject `--two-way` together with `--match-precision < 1` in `validate()`, and show planning failures in dry-run. Long term, fix via A1.
  - Effort: 1 h short term.

#### 🟡 Medium
- **Q1. The fuzzy classification loop is copied three times** (**Fixed:** now one `classifyFuzzyMatches` helper, and the scanners share their path helpers) (`DirectoryDifference.swift:288-312`, `:378-401`, `:485-509`). The scanner's relative-path logic is copied twice (`:604-665` vs `:669-727`). The URL path-join idiom appears about 12 times.
  - Impact: this duplication already caused a divergence (H5a).
  - Recommendation: extract the loop into one helper and add a `joinPath(_:_:)` helper.
  - Effort: 0.5 day.
- **Q2. Error types don't conform to `LocalizedError` and are misused.** ✅ Verified (seen in repro G output).
  - The CLI prints "The operation couldn't be completed. (FilesKit.DirectorySyncError error 1.)" (`Progress.swift:42`).
  - `loadJSONFile` reports a missing *file* as `.invalidDirectory` and a decode error as `.accessDenied` (`DirectoryDifference.swift:849,862`). Every unknown error becomes `.accessDenied` (`:122,174`).
  - Recommendation: add `.fileNotFound` / `.decodingFailed`, and conform both error types to `LocalizedError`.
  - Effort: 2 h.
- **Q3. No input validation.** ✅ Verified (repro O).
  - `--match-precision=-5` is accepted and matches everything.
  - `--deletions` with `--two-way`, and `--show-more-right` with `--deletions`, are silently ignored (`DirectorySync.swift:114-120`).
  - Unknown `.files` keys and invalid values are dropped without a warning (`Config.swift:125-147`). So are invalid `format` values (`CompareCommand.swift:66`).
  - Recommendation: add a `validate()` to each command, and warn about unrecognized config lines.
  - Effort: 2 h.
- **Q4. Docs and behavior disagree.** ✅ Verified (repro N).
  - Help and README advertise `--conflict-resolution source|destination` (`SyncCommand.swift:18-19,37`; `README.md:21,247,275-276`). The parser only accepts `left|right` (`SyncCommand.swift:164-168`).
  - `README.md:213` mentions a `--no-deletions` flag that doesn't exist.
  - The `sync --format` help omits `summary`.
  - Effort: 1 h.
- **Q5. `--no-ignore` also drops the built-in `.files`/`.filesignore` exclusions.** ✅ Verified (repro H).
  - Where: `Ignore()` (`Ignore.swift:140-142`) skips the default patterns that `init(patterns:)` adds (`:146-149`).
  - Impact: config files get copied into the destination, contradicting `README.md:62`. A copied `.files` can carry C2's dangerous settings along with it.
  - Effort: 15 min.

#### ⚪ Low
- **Q6. Dead code.** `SyncProgress.swift` (public struct plus `ProgressHandler`, 0% covered, never used) and `Sequence+Async.swift` (`asyncCompactMap`, never used). Effort: 10 min.
- **Q7. The snapshot JSON schema is defined twice.** Once in `DirectoryDifference.encode` (`DirectoryDifference.swift:49-67`) and again as a hand-built dictionary (`OutputFormatter.swift:248-265`). `printJSON` swallows serialization errors silently (`:282-289`). Use `JSONEncoder` with `.sortedKeys`. Effort: 30 min.
- **Q8. Odd constructs:**
  - `getFileStatus` returns a String status instead of an enum (`DirectoryDifference.swift:918-929`).
  - `try?` around a value that is discarded anyway (`:46`).
  - `… as String?` on a value that is never nil (`Ignore.swift:156-157`).
  - `compareOperation` puts an error message into `relativePath` (`DirectorySync.swift:31-40`).
  - `OperationError.localizedDescription` shadows `Error`'s (`:65-67`).
- **Q9. Ignore semantics differ from `.gitignore`.** Patterns with a slash in the middle aren't anchored to the root (`Ignore.swift:117-120`), but the docs say "Similar to .gitignore". Document the difference or match git.
- **Q10. `cp` hardcodes `recursive: true`** (`CopyCommand.swift:95`), so it has no `--no-recursive` and ignores `recursive` from `.files`.

### 3. Security

No secrets in the repo. The JSON snapshot paths are never used for filesystem access. Relative paths come from enumerating real directories, and I found no path-traversal vector.

#### 🔴 Critical
- **C2. Configs inside untrusted data directories can enable destructive behavior.** ✅ Verified (repro C). **Fixed:** `sync` and `cp` load config with `trustLeft: false`, which drops `deletions`, `twoWay`, `conflictResolution` and `noIgnore` from the source `.files` and prints a warning to stderr. The destination `.files` is still trusted. One gap remains through Q5: an explicit `--no-ignore` copies the source `.files` into the destination, and the next run trusts that copy.
  - Where: `Config.load` reads `.files` from **both** the source and the destination (`Config.swift:44-79`). `deletions`, `twoWay`, and `dryRun` are honored from either one (`SyncCommand.swift:90,96,98`).
  - Impact: in repro C, a `.files` containing `deletions = true` in the **source** folder deleted `precious.txt` from the destination, with no flag passed. Because of C1, and because there is no `--no-deletions`, the user has no CLI way to turn it off. Threat model: syncing from a downloaded archive, a USB stick, a shared or cloud folder, or a repo checkout.
  - Recommendation: never accept `deletions`, `twoWay`, `conflictResolution`, or `dryRun=false` from the source-side config, or accept them only together with an explicit CLI confirmation flag. Print a warning naming the file that changed a destructive setting. Consider loading config from `~/.config/files` plus the destination only.
  - Effort: 0.5–1 day.

#### ⚪ Low
- **S1. File symlinks are followed while comparing.** `contents(atPath:)` follows them (`DirectoryDifference.swift:777-778`), so it can read outside the tree. This only affects comparison, since `copyItem` copies links as links. It is related to P4.
- **S2. Release binaries are unsigned and not notarized, and no checksum is published** (`.github/workflows/release.yml`).

### 4. Performance & Resource Safety

#### 🟠 High
- **H1. An update deletes the destination before copying, so a failure loses data.** ✅ Verified (repro K). **Fixed:** every copy goes to a hidden `.<name>.<uuid>.files-tmp` file next to the destination first. It is then swapped in with `replaceItemAt(…, .usingNewMetadataOnly)` or moved into place. The temp file is removed on failure.
  - Where: `DirectorySync.swift:525-531` runs `removeItem(right)` and then `copyItem`. The chunked path also writes straight to the final path (`:578`).
  - Impact: in repro K the source was unreadable. The destination `a.txt` ("old but precious") was deleted, the copy failed, and **the file is gone**. Ctrl-C or a full disk during a large copy leaves a truncated file under the real name.
  - Recommendation: copy to a temp file in the same directory, then `FileManager.replaceItemAt(_:withItemAt:)` or `rename(2)`.
  - Effort: 0.5 day.
- **H4. Large-file copies (≥10 MB) drop permissions and mtime, and that path has no tests.** ✅ Verified (repro E). **Fixed:** after a chunked copy, the source's permissions and mtime are applied to the temp file before it is swapped in. `copyFileWithProgress` now throws, so it no longer reports success and then failure for the same operation.
  - Where: `copyFileWithProgress` (`DirectorySync.swift:558-640`) streams bytes and sets no attributes.
  - Impact: in repro E, `big.bin` went from `-rwxr-xr-x`, 2020 to `-rw-r--r--`, now, while a small file kept both. Executables lose `+x`, and the "newest" strategy sees fresh mtimes.
  - The same function also yields `.success` progress updates and then a `.failure` for the same operation (`:622-638`), and leaves the partial file behind when the size doesn't match.
  - Recommendation: use `copyfile(3)` with `COPYFILE_ALL` and a progress callback (or `clonefile` on APFS), or apply the source attributes after the stream copy. Combine with H1.
  - Effort: 0.5 day.

#### 🟡 Medium
- **P1. Comparison uses unbounded concurrency and reads whole files into memory.**
  - Where: one task per file (`DirectoryDifference.swift:527-545`, `:736-748`). `filesAreDifferent` loads **both files entirely** before comparing (`:777-783`).
  - Impact: a tree with many large, same-size files (video, disk images) can run out of memory.
  - Recommendation: compare in chunks (`FileHandle`, 1 MB, stop at the first difference) and cap concurrency (a sliding window of about 2 × cores).
  - Effort: 0.5–1 day.
- **P2. Ignored directories are still fully walked.** (**Fixed** together with H2.) `enumerator.allObjects` loads every entry into memory, and filtering happens per file (`DirectoryDifference.swift:688-723`). A 100k-file `node_modules` is enumerated and resource-valued in full.
  - Recommendation: iterate lazily and call `skipDescendants()` on ignored directories. This fixes H2 at the same time.
  - Effort: 2–3 h.
- **P3. Leaf-folders mode compares files twice.** `checkLeftFilesInRight` already compares the content of every left file that exists on the right (`DirectoryDifference.swift:432-436`). Then `findModifiedFiles(commonInLeaves)` reads the same files again (`:442-447`). Drop the second pass. Effort: 30 min.
- **P4. Symlinks aren't handled, which can abort a compare.** ✅ Verified (repro P2).
  - Impact: a symlink to a directory is treated as a file. When both trees contain `link -> real`, `compare` aborts with "Access denied: Could not read file contents" (exit 2). The cause is that the size check uses lstat while `contents(atPath:)` follows the link.
  - Recommendation: read `.isSymbolicLinkKey`, compare link targets, and copy links as links.
  - Effort: 0.5 day.
- **P5. The sync stream can't be cancelled.** `executeFileOperationsStream` starts an unstructured `Task {}` and sets no `onTermination` (`DirectorySync.swift:459-463`). Every operation also runs in `Task.detached` (`:483`). A consumer that stops reading doesn't stop the work.
  - Recommendation: keep a handle to the task, cancel it in `onTermination`, and check `Task.isCancelled` between operations and chunks.
  - Effort: 2 h.
- **P6. A silent fallback flattens the tree.** If the base-path prefix doesn't match, the relative path becomes just `lastPathComponent` (`DirectoryDifference.swift:650-654,712-716`). Files from different directories would then collide silently. The comment at `:690` says "resolve symlinks", but `standardizedFileURL` doesn't do that. Throw instead, or resolve both sides the same way. Effort: 1 h. 🔍

#### ⚪ Low
- **P7. Fuzzy matching is O(L·R) with avoidable costs.** It rebuilds a `URL` for every right-hand file inside the inner loop (`DirectoryDifference.swift:958`), and Levenshtein allocates a full m×n matrix (`StringDistance.swift:19`). Precompute the basenames and use a two-row DP. Effort: 1 h.
- **P8. The order of the failed-operations list is random** because it comes from dictionary iteration (`SyncCommand.swift:149`, `CopyCommand.swift:115`). Sort it before printing.

### 5. Testing

**Measured:** 128 tests in 8 suites (Swift Testing), all passing in 0.09 s. Library line coverage is **85.6%** (1869/2184), with 111/127 functions covered. **CLI target: 0%** (no tests).

| File | Line coverage |
|---|---|
| StringDistance.swift | 100% |
| AsyncStream+OperationResult.swift | 100% |
| Ignore.swift | 94.0% |
| DirectoryDifference.swift | 91.9% |
| Config.swift | 91.5% |
| DirectorySync.swift | **72.4%** |
| Array+OperationResult.swift | 68.2% |
| SyncProgress.swift / Sequence+Async.swift | 0% (dead code) |

**Strengths:** the tests use real temp directories with UUID names. `Ignore`'s glob-to-regex conversion and Levenshtein have good unit coverage. Fuzzy matching and size tolerance have many scenario tests.

#### 🟠 High
- **T1. The CLI layer has no tests, and that is where C1, C2, H3, Q3, Q4, and the dry-run half of H6 live.** **Fixed for C1, C2, H3 and H6:** in-process command tests, plus end-to-end tests that run the built `files` binary. Q3 and Q4 are still untested.
  - Recommendation: extract option resolution (A2) and unit-test the precedence rules. Add a few end-to-end tests that call `Files.parseAsRoot([...])` against temp directories, including the `--format json` | `compare-snapshot` round trip.
  - Effort: 1 day.
- **T2. Risky paths that coverage shows are never run** (`DirectorySync.swift`). **Fixed** except the planning-failure path, which is hard to trigger now that fuzzy two-way sync works:
  - `copyFileWithProgress` (`:562-640`) is entirely untested. H4 would have been caught.
  - The left-newer branch of `keepNewest`, the default strategy, is untested (`:389-398`), as are the equal-mtime and error branches (`:407-413`).
  - The `showMoreRight` info operations are untested at the sync level (`:176-187`), and so is the planning-failure path (`:163-173`).
  - Recommendation: make `minSizeToChunk` injectable, or use an 11 MB fixture.
  - Effort: 0.5 day.

#### 🟡 Medium
- **T3. Missing scenarios**, each tied to a finding above:
  - a `.filesignore` with `dir/` running through a real scan (H2)
  - fuzzy matching combined with ignore patterns or `--no-recursive` (H5a)
  - a determinism test that runs fuzzy matching N times (H5c)
  - two-way sync with fuzzy matching (H6)
  - symlinks (P4)
  - a failure partway through an update leaving the destination intact (H1)
  - `--no-ignore` keeping `.files` out (Q5)
  - Effort: 1 day.

### 6. Maintainability & Tooling

#### 🟠 High
- **H3. Status lines on stdout corrupt the JSON output.** ✅ Verified (repro D, D2). **Fixed:** "Using config/ignore", source-config warnings and the DRY RUN banner all go to stderr.
  - Where: `printConfig` prints "Using config: …" plus a blank line to stdout (`OutputFormatter.swift:19,29,35`). "🔍 DRY RUN" also goes to stdout (`CopyCommand.swift:85`, `SyncCommand.swift:114`).
  - Impact: with any `.files` present, the documented workflow `files compare a b --format json > snap.json` produces invalid JSON, and `compare-snapshot` then fails with exit 2 (`CompareSnapshotCommand.swift:20-23`). Separately, `format = summary` in `.files` overrides an explicit `--format json` (C1).
  - Recommendation: send all diagnostics to stderr.
  - Effort: 1 h.

#### ⚪ Low
- **M1. CI and release process:**
  - `release.yml` publishes binaries without running the tests, and declares no `permissions: contents: write`.
  - The workflows use three different `actions/checkout` versions (v4, v5, v6).
  - The Linux job installs whatever Swift version swiftly picks, not the 6.2.0 pinned in `.tool-versions`.
  - CI has no `swift format lint` step (6 lint warnings today, 1 of them in Sources).
- **M2. The `release` script** has no `set -e`, so it tags and pushes even if the commit fails. It also has no clean-tree or test gate, and `sed -i ''` only works on macOS.
- **M3. Complexity hotspots:**
  - `DirectoryDifference.swift` (981 lines, mixing 4 concerns: models, scanning, strategies, snapshot diff, fuzzy matching)
  - `leafFoldersComparison` (~105 lines)
  - `optimizedComparison` (~87 lines)
  - `copyFileWithProgress` (~82 lines)
  - `SyncCommand.run` (~77 lines)
  - Splitting the file into `Scanner`, `Comparison`, `FuzzyMatcher`, and `Snapshot` would help onboarding.
- **M4. Onboarding is good.** The README is thorough (setup, examples, config tables), and the example config files are well commented. Fix Q4 so the docs can be trusted.

---

## Prioritized Action Plan

### 1. Quick wins (< 1 day total ≈ 1 day)
| # | Fix | Effort |
|---|---|---|
| C1 | Optional Bool flags + `cli ?? config ?? default` in all 3 commands | 2–3 h |
| H3 | Diagnostics → stderr | 1 h |
| H2 | Directory-pattern matching on ancestors | 2–4 h |
| H6 (short) | Reject `--two-way` + fuzzy; surface failures and exit non-zero in dry-run | 1 h |
| Q5 | `Ignore()` keeps default `.files`/`.filesignore` patterns | 15 min |
| Q4 | Fix help/README (`left/right`, `--no-deletions`, override claim) | 1 h |
| P3 | Remove duplicate leaf-folder content comparison | 30 min |
| Q6 | Delete `SyncProgress.swift`, `Sequence+Async.swift` | 10 min |
| M1 | Run tests in `release.yml`, add `permissions`, add a lint step | 1 h |

### 2. Medium-term (1–5 days)
- C2: config trust model for destructive settings (0.5–1 d)
- H1 + H4: atomic temp-file-then-replace copies that preserve metadata (`copyfile`/`clonefile`) (1 d)
- H5: deterministic, scoped, ignore-aware fuzzy matching (1 d)
- P1 + P2: streaming chunked compare, bounded concurrency, pruned enumeration (1 d)
- P4 symlinks (0.5 d), P5 cancellation (2 h), Q2 error types (2 h), Q3 validation (2 h)
- A2 + T1: shared option resolution plus CLI tests (1.5 d)
- Q1/A3: deduplicate the comparison strategies (1 d)
- T2/T3: fill the coverage gaps listed above (1.5 d)

### 3. Long-term (> 5 days)
- A1: redesign `DirectoryDifference` to carry left↔right match pairs, so fuzzy matching works correctly for sync and two-way.
- A4: a two-way sync state file, so deletions propagate and real conflicts are detected (both sides changed since the last sync).
- Signed/notarized releases with published checksums (S2), and Linux CI pinned to the toolchain in `.tool-versions`.

---

## Metrics
- **Files analyzed:** 22 Swift files (16 source, 6 test) plus CI, release script, README, and example configs
- **Lines of code:** 3,074 source (FilesKit 2,202 · CLI 872) · 3,514 test · 6,588 total
- **Tests:** 128 in 8 suites, 100% passing, 0.09 s
- **Test coverage:** 85.6% lines in FilesKit (1869/2184) · 0% in CLI target
- **Complexity hotspots:** 5 (listed in M3)
- **Build:** clean, with Swift 6 language mode in every target · `swift format lint`: 6 warnings
- **Dependencies:** 1 (swift-argument-parser 1.6.2, pinned)
- **Not verified:** the Linux build and tests (the audit ran on macOS only); P6 and the H5b/H5d edge cases are from code review only.

---

## Appendix — Reproductions

Built from `1947d51` with `swift build` (`.build/debug/files`). Each case ran in fresh temp directories. My `~/.filesignore` contained only `.DS_Store`.

```bash
# A — dir-only ignore pattern doesn't apply (H2)
mkdir -p l/node_modules r; echo x > l/node_modules/a.js; printf 'node_modules/\n' > l/.filesignore
files compare l r -v            # → lists node_modules/a.js under "Only in LEFT"

# B — .files overrides --dry-run (C1)
mkdir -p l r; echo x > l/new.txt; printf 'dryRun = false\n' > l/.files
files sync l r --dry-run; ls r  # → new.txt was really copied

# C — source-side .files enables deletions (C2)
mkdir -p l r; echo x > l/a.txt; echo precious > r/precious.txt; printf 'deletions = true\n' > l/.files
files sync l r; ls r            # → precious.txt deleted

# D — JSON corrupted by "Using config:" (H3)
printf 'recursive = true\n' > l/.files
files compare l r --format json > snap.json; files compare-snapshot snap.json snap.json  # → exit 2, invalid JSON

# E — ≥10 MB copy loses mode/mtime (H4)
dd if=/dev/urandom of=l/big.bin bs=1m count=11; chmod 755 l/big.bin; touch -t 202001010000 l/big.bin
files cp l r; stat -f "%Sp %Sm" r/big.bin   # → -rw-r--r--, current time

# F / M — fuzzy matches an ignored file / a nested file under --no-recursive (H5a)
echo same > l/report1.txt; echo same > r/report2.txt; printf 'report2.txt\n' > r/.filesignore
files cp l r --dry-run --match-precision 0.8   # → "No operations needed" (report1.txt never copied)

# G — two-way + fuzzy aborts; dry-run exits 0 (H6)
echo aaaa > l/notes1.txt; echo bbbbbbbb > r/notes2.txt
files sync l r --two-way --match-precision 0.8   # → "Planning failed … no such file", 0 ops

# H — --no-ignore copies .filesignore (Q5)
# I — non-determinism: l/{file_ab.txt,file_abcd.txt}, r/file_abc.txt, 20× compare → 6 vs 14 split (H5c)
# K — unreadable source on update: destination deleted, copy fails, file lost (H1)
chmod 000 l/a.txt; files cp l r   # r/a.txt existed before → gone after
# N — --conflict-resolution source → "invalid value" (Q4)
# O — --match-precision=-5 accepted (Q3)
# P2 — identical trees each containing `link -> real` → compare exits 2 (P4)
```
