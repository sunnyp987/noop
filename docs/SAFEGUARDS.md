# Platform safeguards — staying within GitHub's Acceptable Use Policy

NOOP's account was once auto-suspended by GitHub (later **reinstated on appeal** — the review found no violation). The most likely trigger was **automated pattern-matching**, not anything we actually did wrong: an anonymous account that, in a short window, cut a rapid burst of releases and posted repeated promotional text. To a spam filter that looks bot-like, even though it was one developer shipping fast and answering everyone.

NOOP's purpose is legitimate — it reads a device **you own** over Bluetooth, fully offline, with no account, no cloud, and no proprietary code. None of that breaks GitHub's terms or any law. These safeguards exist so our **behaviour never again *looks* like abuse** to an automated filter. They're grounded in [GitHub's Acceptable Use Policies](https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies) and [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).

## The relevant policy lines

GitHub's AUP prohibits, and may suspend accounts for:
- **"excessive automated bulk activity"** and **"automated inauthentic activity"** (§4)
- **"bulk distribution of promotions and advertising"** and **"monetized or excessive bulk content in issues"** (§4 / §10)
- activity that **"significantly or repeatedly disrupts the experience of other users"**
- **"excessively frequent requests to GitHub via the API"** → temporary or permanent suspension (ToS §H)

## Our safeguards

**1. No payment solicitation in issues, PRs, comments, or docs.**
Keep repository communication focused on support, releases, bugs, and interoperability research. Repeated promotional text can be misread as "promotional bulk content / solicitation" by automated filters.

**2. Batch releases — don't drip-ship.**
Combine multiple fixes into one release and space releases out. `Tools/release.sh` has a **cadence guard**: it refuses to publish if ≥3 releases were cut today or the last was <20 min ago, unless you deliberately set `ALLOW_RAPID_RELEASE=1`. A burst should always be a conscious decision, never an accident. (Tune via `CADENCE_LIMIT` / `CADENCE_MIN_GAP_MIN`.)

**3. No mass-identical comments.**
When replying across many issues/PRs (e.g. a board sweep), vary the wording and/or space the posts out. A flood of identical comments reads as inauthentic activity.

**4. Throttle automated API activity.**
Batch API operations; don't burst-create commits, issues, or comments. Stats badges (`refresh-stats-badges.py`) write to the working tree and ride the normal commit — they no longer push a burst of API commits.

**5. Keep GitHub Actions narrow and intentional.**
Actions is enabled for build/test verification and release artifacts only. Avoid workflows that post comments, open issues, or create frequent automated releases. Keep API activity low, prefer manual `workflow_dispatch` for release publishing, and review any third-party `uses:` before adding it.

**6. Keep recoverability simple.**
Clone the repository locally before releases and keep release artifacts attached to GitHub Releases. If GitHub ever flags the repository again, appeal calmly on the facts above instead of evading the suspension or creating replacement accounts.

## If it happens again
Don't evade or create replacement accounts (that makes a suspension permanent and violates the rules). Appeal at support.github.com with the facts: NOOP reads a device the user owns, offline, no account/cloud/credentials, no proprietary code — there is nothing to violate. The appeal worked once; the facts haven't changed.
