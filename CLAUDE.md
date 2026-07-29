# Working agreement

## Shipping

This project is young and has one developer with push access, so the pull
request step buys nothing. Skip it.

When a task is finished **and verified**, ask the developer whether it can go.
On a yes, push straight to `main`. Do not open a PR, do not ask them to merge
one.

"Verified" means the checks below actually ran and passed, not that the code
looks right:

```bash
./scripts/run-logic-tests.sh          # 166 checks, seconds
xcodebuild build -project OffiCraft.xcodeproj -scheme OffiCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

For anything that changes what a screen looks like, also screenshot it on the
simulator and look at the image — see the Simulator section in `README.md`.

Never force-push and never rewrite history on `main`.

## After pushing: hand over the .ipa

Pushing to `main` triggers the `Build` workflow, which runs the logic tests, a
simulator build and the unsigned archive, then uploads `OffiCraft-ipa`
(30-day retention).

Do not stop at "pushed". Wait for that run and give the developer a link they
can click to download the build:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
RUN=$(gh run list --branch main --workflow Build --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status
ART=$(gh api "repos/$REPO/actions/runs/$RUN/artifacts" -q '.artifacts[0].id')
echo "https://github.com/$REPO/actions/runs/$RUN/artifacts/$ART"
```

Paste that URL in the reply. It downloads the `.ipa` directly for anyone signed
in to GitHub. If the run fails, report the failing step and its log — do not
report the push as done.

The build is unsigned. Installing on a device still needs resigning with a
profile covering `link.hardcore.officraft` and `link.hardcore.officraft.widgets`.
