# State

## App Store review: 1.1.0 (build 5)

App Review replied with Guideline 2.1 - Information Needed. They want a screen recording
from launch, plus answers on purpose, setup, external services, regional differences
and regulated content. The answers go in the Resolution Center reply and in
App Review Information > Notes.

### Done

- Written answers: `store-listing/review-reply.md`, below the `---` line.
- Recording plan: the same file, top section.
- Prep script: `store-listing/tools/recording.sh` (`prep`, `restore`, `shrink`).

### Next

1. Add build 5 to an internal TestFlight group and install it on the Mac. It replaces
   the Homebrew (Developer ID) copy in /Applications.
2. Try the in-app Settings > About > Grant… button on that build. If it does nothing
   (the sandbox hides the system prompt), consider building the in-app Accessibility
   guide before resubmitting.
3. `store-listing/tools/recording.sh prep`, turn on Do Not Disturb, record with ⌘⇧5
   following the plan.
4. `recording.sh restore`, then `brew reinstall --cask pastiche`.
5. If the .mov is large: `recording.sh shrink <file.mov>`.
6. In App Store Connect: reply with the text and attach the recording, paste the same
   text into App Review Information > Notes.
