#!/usr/bin/env bash
# Writes every commit's date and message, newest first and grouped by the
# release it went out in, as Lua for the What's new > All changes page.
#   Tools/commits.sh                       -> ChangelogCommits.dev.lua (the dev copy's, not packaged)
#   Tools/commits.sh ChangelogCommits.lua  -> the released file (the release workflow runs this)
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-ChangelogCommits.dev.lua}"

{
	echo "-- Made by Tools/commits.sh: every commit, newest first. Don't edit by hand."
	echo "local _, ns = ..."
	echo "ns.CHANGELOG_COMMITS = {"
	# Each release's commits: from the tag before it up to its tag (the newest
	# tag's are followed by any not released yet, as "next").
	prev=""
	ranges=()
	for tag in $(git tag --list 'v*' --sort=v:refname); do
		ranges+=("${prev:+$prev..}$tag ${tag#v}")
		prev="$tag"
	done
	ranges+=("${prev:+$prev..}HEAD next")
	for (( i = ${#ranges[@]} - 1; i >= 0; i-- )); do
		read -r range version <<< "${ranges[$i]}"
		git log --no-merges --format='%as%x09%s' "$range" | while IFS=$'\t' read -r date subject; do
			# (a long string, so quotes and backslashes need no escaping)
			subject="${subject//]==]/] ==]}"
			printf '\t{ "%s", "%s", [==[%s]==] },\n' "$version" "$date" "$subject"
		done
	done
	echo "}"
} > "$out"
echo "wrote $out"
