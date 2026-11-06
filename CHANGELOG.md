# Changelog

## 2.2

- Settings now lists all your repositories instead of only the first 200. Thanks to @tiagolpadua.
- Selecting all repositories now tells you how many you're selecting and warns that many repositories can hit GitHub's rate limit.
- The menu now opens at its full height right away. Before, it opened short and only grew after you'd opened Settings.

## 2.1

- Settings are saved as soon as you change them, so closing the menu without pressing Done no longer loses your changes.
- If a repository's runs fail to load, the menu now says so ("Couldn't load runs for …") instead of showing it as having no runs. One failing repository no longer hides the runs of all the others.
- Settings now shows an error when the repository list can't be loaded.
- Completion notifications now also fire for runs that were waiting, pending or requested, and for runs that were briefly hidden by a filter or a failed fetch.
- Repositories from a second GitHub App installation are no longer skipped.
- Fixed spurious "Network error" messages after changing the polling interval or on Keychain errors.
- Pressing Done in Settings refreshes right away instead of waiting for the next poll.
- Fixed several cases where a request finishing after sign-out could restart polling or show stale data.

## 2.0

ActionBar is now open source and distributed directly instead of through the Mac App Store.

- Automatic updates via Sparkle. Use "Check for Updates…" in About to check manually.
- New option to include workflow runs triggered by other users.
- The menu bar icon now shows the status of running and queued workflows first.
- Fewer API requests: unchanged workflow runs are served from cache using conditional requests.
- Fixed the repository list layout in Settings.

If you're coming from the App Store version, you'll need to sign in again.
