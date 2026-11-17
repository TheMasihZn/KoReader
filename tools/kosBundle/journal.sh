#!/bin/sh
# Change journal and restore points. Nothing here deletes or rewrites history.
#   journal.sh note "what changed"      append a line with the current commit to doc/changeJournal.md
#   journal.sh point name               tag the current commit as restore point kosRestore<name>
#   journal.sh list                     show restore points, newest last
#   journal.sh undo <commit>            make a NEW commit that reverses <commit> (git revert); history stays
#   journal.sh back <name>              open a new branch kosBack<name> at that restore point; nothing is lost
#   journal.sh save                     write a timestamped git bundle of everything to out/ (never overwrites)
set -e
cd "$(dirname "$0")/../.."
case "$1" in
  note)  printf -- '- %s `%s` %s (branch %s)\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(git rev-parse --short HEAD)" "$2" "$(git branch --show-current)" >> doc/changeJournal.md ;;
  point) git tag "kosRestore$2" ;;
  list)  git tag -l 'kosRestore*' --sort=creatordate ;;
  undo)  git revert --no-edit "$2" ;;
  back)  git checkout -b "kosBack$2" "kosRestore$2" ;;
  save)  mkdir -p out; f="out/kos-$(date -u +%Y%m%dT%H%M%SZ).bundle"; git bundle create "$f" --branches --tags ^origin/master; echo "$f" ;;
  *) sed -n 2,9p "$0" ;;
esac
