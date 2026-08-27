# brewup cache paths — the one definition, shared by the writer and both readers.
#
# Deployed to ~/.local/lib/brewup-paths.sh and sourced by:
#   dot_zshrc                                 brewup() writes the failure marker
#   dot_local/bin/executable_chezmoi-drift-check   reads it for the banner segment
#   dot_local/bin/executable_chezmoi-fix           reads it for the failure notice
#
# Before this file existed the marker path was a literal in all three, and a
# path edit in any one of them was a silent no-op: the marker kept being
# written, the readers kept looking elsewhere, and nothing reported anything.
# A bats test pinned the literal across the three files to compensate; that
# textual pin is replaced by the sharing this file provides.
#
# POSIX sh only — a zsh startup file and two bash executables all source it.
# Assignments and comments, nothing else: no arrays, no `local`, no functions,
# no side effects. Safe to source repeatedly and in any order.
#
# Deliberately $HOME/.cache and NOT $XDG_CACHE_HOME, unlike the chezmoi-drift
# state file which is XDG-aware. Every brewup file is written under $HOME/.cache
# unconditionally, so honouring XDG here would point the readers at a path
# nothing ever writes the moment XDG_CACHE_HOME is set. Moving brewup onto XDG
# is a separate decision that would have to move the writer too.
#
# Consumers keep a fallback default matching each value below, so that a fresh
# or partially-applied $HOME (where this file does not exist yet) degrades to
# today's behaviour instead of breaking shell startup.

# shellcheck disable=SC2034  # sourced for its variables; nothing is used here

BREWUP_STAMP="$HOME/.cache/brewup.last"  # date of the last daily run attempt
BREWUP_FAIL="$HOME/.cache/brewup.failed" # present => that run failed
BREWUP_LOG="$HOME/.cache/brewup.log"     # daily run output, tailed by `brewlog`
BREWUP_LOCK="$HOME/.cache/brewup.lock"   # lock dir guarding concurrent runs
