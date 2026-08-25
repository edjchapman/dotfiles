# Zsh Framework Modernisation

This repo stays on **oh-my-zsh + agnoster**. Proposals to swap the framework for a
lighter base — no-framework plus starship or powerlevel10k, zinit, zi, antidote —
are out of scope.

## Why this is out of scope

The case for a swap is almost always startup latency, so the question was settled
with a measurement rather than an argument. From the 2026-08-18 zsh-environment
review:

| Component | Cost | Share |
|---|---|---|
| Warm interactive startup (`zsh -i -c exit`, 5 runs) | **~200ms** | 100% |
| oh-my-zsh | **~110ms** | ~55% |
| bare zsh | ~20ms | ~10% |
| `brew --prefix` / `fnm env` / `fzf --zsh` | ~10ms each | ~15% |

(First cold run was 500ms; the `brew --prefix` fork was eliminated in #144.)

So oh-my-zsh is the only startup cost that matters, and **~110ms is the ceiling on
what any framework swap could recover**. Total warm startup at 200ms sits
comfortably below the threshold where a human notices a shell opening. The upside
is capped at something imperceptible.

Against that capped upside sits real, uncapped churn:

- The oh-my-zsh SHA is the repo's **only** chezmoi external, pinned in
  `.chezmoiexternal.toml` and kept current by the weekly `update-externals.yml`
  draft PR. That machinery exists, works, and is understood.
- `agnoster` is load-bearing for the prompt's appearance across both machine types.
- A framework swap touches the file whose breakage is hardest to recover from — a
  bad `~/.zshrc` can leave the next shell unable to start (see the pitfall in
  `CLAUDE.md`).

The repo's stated ethos is **stability over fashion**. A change that risks the
shell's boot path to reclaim at most 110ms of imperceptible latency is the exact
trade this ethos exists to decline.

## What would reopen this

This is a decision on the *current* evidence, not a permanent ban. It should be
revisited if:

- **Warm startup regresses meaningfully** past ~200ms and oh-my-zsh is again the
  dominant term. The measurement above is the baseline to compare against.
- **The theme or plugin needs change** such that agnoster / oh-my-zsh no longer
  cover them — i.e. the swap is motivated by capability, not by speed.
- **oh-my-zsh becomes unmaintained**, making the pin a liability rather than a
  stable base.

Note that the first two are *capability or regression* triggers. "A lighter setup
is more modern" is not one, and is precisely the reasoning this file exists to
short-circuit.

## Prior requests

- #140 — "Evaluate modernising the zsh stack (oh-my-zsh/agnoster vs lighter alternatives)"
