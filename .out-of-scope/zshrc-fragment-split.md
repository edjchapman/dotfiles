# Splitting dot_zshrc into Sourced Fragments

`dot_zshrc` stays a single file. Proposals to extract its subsystems (drift
banner, `brewup()`, the brew/mas/chezmoi wrappers) into per-topic fragments
under `dot_config/zsh/` — sourced from a slimmed-down zshrc — are out of scope.

## Why this is out of scope

The proposal was originally a conjunction: fragments would (a) let the bats
suite source real files instead of sed-extracting line ranges, and (b) create a
home for constants shared with the bash helpers. Both halves were dismantled by
triage on #146:

- **The shared-constants win shipped without the split.** The brewup cache
  paths were irreducibly cross-dialect — `brewup()` is zsh (`emulate -L zsh`,
  `print -P`), while both readers (`chezmoi-fix`, `chezmoi-drift-check`) are
  bash — so a zsh fragment could never have served them anyway. #152 landed the
  correct seam instead: a POSIX-`sh` file, `~/.local/lib/brewup-paths.sh`,
  sourced by all three. That removed the strongest argument for fragments and
  simultaneously proved that `dot_zshrc` can source a deployed file where a
  genuine cross-file need exists.

- **The testability win was marginal on measurement.** Of the 8 sed
  extractions targeting `$ZSHRC` in `tests/drift-check.bats`, 5 are `grep -c`
  assertions on source *text* — fragments would give those a smaller file to
  grep, not a behavioural test. The 3 behavioural extractions already work:
  they carry explicit vacuous-pass guards (`[ -s ]` + a content `grep -q`), and
  #152's own tests adopted the same guarded idiom for its new extraction. The
  sed-extraction pattern is the suite's documented testing idiom, not a wart.

- **The costs are real and the repo's ethos declines this trade.** Fragments
  make sourcing order explicit configuration that can silently break, multiply
  the files deployed to `$HOME`, and give up the single-file greppability the
  repo leans on — all in the boot-path file whose breakage is hardest to
  recover from (a bad `~/.zshrc` can leave the next shell unable to start).
  The recorded stance from the zsh-framework decision applies verbatim:
  stability over fashion; do not risk the shell's boot path for imperceptible
  gains.

```bash
# The documented testing idiom: extract, then guard against the anchor
# silently matching nothing (tests/drift-check.bats).
extract_banner_block() {
    sed -n '/^# chezmoi drift banner/,/^fi$/p' "$ZSHRC" >"$TMPHOME/banner.zsh"
    [ -s "$TMPHOME/banner.zsh" ]
    grep -q 'chezmoi:' "$TMPHOME/banner.zsh"
}
```

## What would reopen this

This is a decision on the current evidence, not a permanent ban. Revisit if:

- **`dot_zshrc` grows substantially** past its current ~350 lines, to the point
  where new subsystems are being added and single-file navigation demonstrably
  breaks down.
- **An extraction guard fails in anger** — i.e. a layout change silently breaks
  a sed anchor in a way the `[ -s ]`/`grep -q` guards fail to catch, producing
  a vacuous pass that ships a real bug.
- **A subsystem needs behavioural tests the extraction idiom cannot support**
  — something the guarded sed-and-source pattern demonstrably cannot reach.

"Fragments are cleaner" is not a trigger; the layout cost was weighed and
declined with the mechanism already proven available (#152) for cases that
earn it.

## Prior requests

- #146 — "Structure: extract the tested dot_zshrc blocks (banner, brewup) into sourced fragments"
