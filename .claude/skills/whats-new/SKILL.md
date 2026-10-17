---
name: whats-new
description: Run before every commit in the Cinematic repo. Reviews the changes being committed, decides whether any is a new feature worth listing on the in-game What's new > New features page, and if so drafts the entry and asks the user to approve it before adding it to Changelog.lua (and esES.lua) in the same commit.
---

# What's new check (before each commit)

Cinematic's settings end with a **What's new** hub of two pages:

- **New features** (`Changelog.lua`, `ns.CHANGELOG_FEATURES`): picked by hand,
  only with the user's OK. This skill is how entries get there.
- **All changes**: every commit message, generated at release time by
  `Tools/commits.sh` (the release workflow runs it). Nothing to do for it here,
  but the commit message is shown to players as written, so keep it readable.

## Steps

1. **Look at what's being committed**: your own changes only (other sessions
   may have edits in the same checkout). Use `git diff` on your files, or
   `git diff --cached` once staged.

2. **Decide if there's a new feature.** It's worth listing when a player would
   notice it and want to know: a new option, page, camera, behaviour or
   supported addon. It isn't when it's a fix, a tweak to how something already
   works, a debug command, a refactor, a translation, a default changed, or
   anything internal. When unsure, ask instead of skipping. If there's nothing,
   say so in one line and go on with the commit.

3. **Draft the entry** for each feature:
   - `date`: today (YYYY-MM-DD)
   - `title`: a few words
   - `text`: one or two short sentences for players: what it does, not how
   - `page`: the English name of the settings page it's on, as `ns.OpenOptions`
     takes it (a `RegisterSubpage` name in Options.lua, e.g. "Nameplates",
     "Chat", "General"); nil if none. Its icon comes from the page.
   - `client`: "forever" or "retail" only if it exists on just that client

4. **Ask the user to approve** with AskUserQuestion, showing the drafted title
   and text in the question or preview. Options: add it as written (recommended),
   skip it. They can pick Other to reword. Never add an entry without a yes.

5. **On approval**: add the entry at the top of `ns.CHANGELOG_FEATURES` in
   `Changelog.lua`, add the Spanish for its title and text to the end of
   `Locales/esES.lua` (under the "What's new" block; check the key isn't there
   already), run `luacheck .`, and include both files in the commit.
