# Pastiche

Pastiche is an open-source clipboard manager for macOS: a small, keyboard-driven
history of what you have copied. Press a shortcut, arrow through it, press Return
to paste it back where you were.

It keeps text snippets and images, filters by type, and searches inline. That
is the whole feature set — it is deliberately not a clipboard suite.

- Menu bar only: no Dock icon, no windows in your way.
- Text **and** image history, with large inline previews.
- Filter by type: All / Text / Images.
- Inline search, reachable with `Tab`.
- History survives quit and reboot.
- Password-manager copies are ignored by default.

Requires macOS 14 or later. Releases are universal (Apple silicon and Intel). A
plain `make` builds only for the Mac it runs on; add `UNIVERSAL=1` for both.

## Install with Homebrew

```sh
brew tap bcollard/pastiche
brew trust --tap bcollard/pastiche   # Homebrew 6.0+ requires trusting third-party taps
brew install --cask pastiche
```

Or download the zip from the [releases page](https://github.com/bcollard/pastiche/releases).

## Build and run

No Xcode project to open — Swift Package Manager builds it and a `Makefile`
assembles the app bundle.

```sh
git clone https://github.com/bcollard/pastiche.git
cd pastiche
make run          # build, bundle into dist/, and launch
```

Other targets:

| Target           | What it does                                           |
| ---------------- | ------------------------------------------------------ |
| `make build`     | Compile the executable only                            |
| `make app`       | Assemble `dist/Pastiche.app`                  |
| `make run`       | `make app`, then relaunch it                           |
| `make install`   | Copy the bundle into `/Applications`                   |
| `make uninstall` | Remove it from `/Applications`                         |
| `make requirement` | Print the code-signing requirement macOS matches on  |
| `make notarize`  | Sign, notarize and staple for distribution             |
| `make release VERSION=x.y.z` | Universal + notarized + `dist/Pastiche-x.y.z.zip` and checksum |
| `make appstore`  | Sandboxed, store-signed `.pkg` (needs `PROFILE=`, see Distribution) |
| `make clean`     | Delete `.build/` and `dist/`                           |

The app icon is generated from `Tools/make_icon.swift`, so the repository
carries no binary assets.

## Keyboard

The popup is meant to be used without touching the mouse.

| Key            | Action                                                  |
| -------------- | ------------------------------------------------------- |
| `⌘'`           | Open or close the popup (configurable)                  |
| `↑` `↓`        | Move through the list                                   |
| `←` `→`        | Switch type filter: All / Text / Images                 |
| `Tab`          | Jump into the search field, and back out                |
| *any letter*   | Starts searching straight away, no `Tab` needed         |
| `Return`       | Paste the selected item (configurable to `⌘Return`)     |
| `⌘1`…`⌘9` `⌘0` | Paste the item carrying that number                     |
| `⌫`            | Delete the selected item (configurable)                 |
| `⌘⌫`           | Delete the selected item, always                        |
| `⌘⇧⌫`          | Clear the whole history                                 |
| `Esc`          | Clear the search, or close the popup if it is empty     |
| `⌘,`           | Open Settings                                           |
| `PgUp` `PgDn`  | Jump eight rows                                         |
| `Home` `End`   | First / last item                                       |

Search and page-down both respect the active type filter, so narrowing to
`Images` and then searching stays inside images.

Bare `⌫` only deletes while the caret is outside the search field, where it has
to stay as ordinary text editing; `⌘⌫` deletes from either place. *Settings →
General → Delete entry with* switches the bare key off if you would rather only
`⌘⌫` removed things.

The search box clears every time the popup opens, but the **type filter is
sticky** — it stays where you left it until you change it, the way Copy 'Em
behaves. The segmented control at the top always shows which filter is live.

## Permissions

The app asks for **Accessibility** the first time it pastes. It needs it only
to press `⌘V` in the app you came from; the popup, the shortcut, and the
history all work without it. If you decline, turn off *Paste into the active
app automatically* in Settings and the app will only put the item on your
clipboard for you to paste yourself.

Grant it under *System Settings → Privacy & Security → Accessibility*. If the
About tab still reads *Not granted* a moment after you granted it, press
**Relaunch** — a few macOS builds only hand the new grant to a fresh process.

Until it is granted the popup shows an inline banner rather than re-raising the
system modal on every paste; the system prompt appears at most once per run.

**A toggle that is switched on does not always mean granted.** macOS stores the
grant against the app's code-signing requirement, so if the signature changed
since you approved it — ad-hoc to Developer ID, say — the entry stays visibly
enabled while silently failing to match. Clear it and approve once more:

```sh
tccutil reset Accessibility io.github.bcollard.Pastiche
```

**The signature decides whether that grant sticks.** macOS ties an Accessibility
grant to the app's code-signing requirement. An ad-hoc signature pins it to the
`cdhash`, which changes on *every* build, so each rebuild looks like a different
app and silently loses the grant. `make app` therefore signs with a Developer ID
certificate whenever the keychain has one, which keys the requirement to the team
identifier instead:

```sh
make requirement
#   designated => identifier "io.github.bcollard.Pastiche"
#                 and anchor apple generic and ... certificate leaf[subject.OU] = <TEAM>
```

Without a certificate the build still works, signed ad-hoc, and `make app` says
so — expect to re-grant Accessibility after each rebuild. Switching between the
two also invalidates the old grant once: remove *Pastiche* from the
Accessibility list with the **−** button, then add it again.

The global shortcut itself uses Carbon's `RegisterEventHotKey`, which needs no
permission at all — that is why it is used in preference to an `NSEvent`
global monitor.

## Privacy

Everything stays on your Mac. There is no network code in this app.

Three filters are on by default, and configurable under *Settings → Privacy*:

- **Concealed items** are skipped. Apps that follow the
  [nspasteboard.org](http://nspasteboard.org) convention mark copied secrets with
  `org.nspasteboard.ConcealedType`; 1Password does. An app that does not mark its
  secrets is recorded like any other, which is what the ignored-apps list is for.
- **Transient and auto-generated items** are skipped — content an app put on
  the pasteboard programmatically, which you never actually copied.
- **Ignored apps**: copies made while a listed app is frontmost are never
  recorded. 1Password, Bitwarden and Keychain Access are pre-filled.

History lives in `~/Library/Application Support/Pastiche/`: text in
`history.json`, images as PNGs in `images/`. Nothing is encrypted, so treat
that directory as you would any other file of your own notes. *Clear history*
in Settings deletes both.

## Importing from Copy 'Em

`Tools/import_copyem.py` pulls recent entries out of Copy 'Em's Core Data store
and writes them into this app's history, converting images to PNG.

```sh
pkill -f "Pastiche.app"          # it must not be running
python3 Tools/import_copyem.py --limit 200
open "/Applications/Pastiche.app"
```

`--dry-run` reports what would be imported without writing anything. Copy 'Em's
own files are never modified: the store is copied to a temporary directory and
opened read-only.

Two differences from Copy 'Em worth expecting. Copy 'Em keeps every copy as its
own row, while this app deduplicates, so 200 Copy 'Em entries typically collapse
to fewer items. And where an entry carries both text and an image — a copy out of
a browser, say — the text is kept, matching what `PasteboardMonitor` does live.

Imported images are hashed as written, and the app hashes its own re-encoded PNGs,
so copying an imported image again creates one duplicate entry. Harmless, and only
once per image.

## How it works

| File                    | Responsibility                                          |
| ----------------------- | ------------------------------------------------------- |
| `PasteboardMonitor`     | Polls `NSPasteboard.changeCount`, applies privacy filters |
| `ClipboardStore`        | Ordered, deduplicated, capped history plus its disk mirror |
| `HotKeyCenter`          | Carbon global hotkey registration                       |
| `PopupController`       | The floating panel and every keystroke inside it        |
| `PopupView` / `PopupModel` | SwiftUI list, filtering, selection                   |
| `Paster`                | Writes to the pasteboard and posts the synthetic `⌘V`   |

Two details worth knowing if you are changing the code:

- Keyboard handling lives in a single `NSEvent` local monitor in
  `PopupController`, not in SwiftUI. That is what lets `↑`/`↓` drive the list
  while the caret is inside the search field.
- After pasting, `PasteboardMonitor.suppressedFingerprint` swallows exactly one
  pasteboard change — our own write — so pasting does not re-record the item.

## Distribution

### Direct download (what this repo is set up for)

```sh
xcrun notarytool store-credentials NOTARY \
  --apple-id <your-apple-id> --team-id <TEAM> --password <app-specific-password>
make notarize
```

That signs with Developer ID, submits to Apple, waits, and staples the ticket, so
the app opens on any Mac without a Gatekeeper warning. Everything described in
this README works under this model.

#### Releasing

Push a tag and the `Release` workflow does the rest: a universal build, Developer ID
signing, notarization, a GitHub release with the zip and its checksum, and an update
of the cask in [bcollard/homebrew-pastiche](https://github.com/bcollard/homebrew-pastiche).

```sh
git tag v1.0.0 && git push origin v1.0.0
```

To test the whole pipeline without releasing anything, run the workflow by hand from
the Actions tab; the signed zip comes back as a downloadable artifact.

It needs these repository secrets (`gh secret set NAME -R bcollard/pastiche`):

| Secret | What |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, exported as `.p12`, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password chosen when exporting the `.p12` |
| `NOTARY_APPLE_ID` | Apple ID used for notarization |
| `NOTARY_TEAM_ID` | Team ID (`PZARL6555S`) |
| `NOTARY_PASSWORD` | App-specific password from appleid.apple.com |
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with *Contents: write* on `bcollard/homebrew-pastiche` |

A missing secret fails the run in seconds, before any macOS build minutes are spent.
The tap repository must be public for other people to `brew tap` it.

### Mac App Store

The store requires the **App Sandbox**. An earlier version of this section said a
sandboxed process cannot post the synthetic `⌘V`. That was wrong, and it is
corrected here with what was actually measured.

A minimal sandboxed probe (Developer ID-signed, `com.apple.security.app-sandbox`
on) was added to the Accessibility list by hand. It then reported
`AXIsProcessTrusted() == true`, posted `⌘V` through `CGEvent`, and the text landed
in a TextEdit document. A sandboxed build of this app also recorded pasteboard
copies and opened its popup from the global hotkey.

| Capability | Sandboxed? | Evidence |
| --- | --- | --- |
| Polling `NSPasteboard` | ✅ Works | Sandboxed build recorded a copy |
| Carbon global hotkey | ✅ Works | Sandboxed build opened the popup |
| History under Application Support | ✅ Redirected into the container | Container created, `history.json` written |
| Synthetic `⌘V` paste | ✅ Works **after a manual grant** | Probe pasted into TextEdit |
| **System Accessibility prompt** | ❌ **Never appears** | See below |
| Login item via `SMAppService` | Not tested | |
| Frontmost-app attribution | Not tested | |

**The catch is the permission flow, not the paste.** Under the sandbox,
`AXIsProcessTrustedWithOptions(prompt: true)` shows no dialog and the app does not
add itself to the Accessibility list. The identical probe without the sandbox
entitlement showed the dialog in 9 of 48 samples taken every 0.25 s; the sandboxed
one showed it in 0 of 48. A store build therefore needs its own onboarding: open
*Privacy & Security → Accessibility* and walk the user through **+** → choose the
app → enable it, instead of relying on the system prompt.

What is **not** established:

- The probe was signed with Developer ID, not with the *Apple Distribution*
  identity a store build uses. The behaviour is expected to match; that is untested.
- Whether App Review accepts a clipboard manager that posts keystrokes is unknown.
  Say plainly in the review notes what the app records and why it asks for
  Accessibility.
- Copy 'Em ships a separate paste helper. This test does not explain why, so its
  reasons may not apply here.

Two workable paths:

1. **Direct distribution** (what the repo is set up for). Unsandboxed, the native
   Accessibility prompt works, and there is no container to migrate to.
2. **A sandboxed store build** with the manual-grant onboarding above.

#### Building the store package

Certificates differ from direct distribution: notarization uses *Developer ID
Application*, while the store needs *Apple Distribution* to sign the app and
*Mac Installer Distribution* to sign the `.pkg`. Create both in Xcode (*Settings →
Accounts → Manage Certificates → +*) or on the developer portal.

1. **Register the App ID** at *Certificates, IDs & Profiles → Identifiers → +*.
   Use an explicit bundle ID matching `BUNDLE_ID` in the `Makefile`. It cannot be
   changed once an App Store Connect record exists.
2. **Create the App Store Connect record** for that bundle ID.
3. **Create a provisioning profile**: *Profiles → + → Mac App Store Connect*, pick
   the App ID and your Apple Distribution certificate, and download it.
4. **Build:**

   ```sh
   make appstore PROFILE=~/Downloads/Pastiche.provisionprofile
   ```

   This produces `dist/appstore/Pastiche.pkg`: a sandboxed copy of the app,
   signed with Apple Distribution, with the profile embedded and the team and
   application identifiers written into its entitlements, wrapped in a package
   signed with the installer certificate. `make appstore` refuses to run, with a
   message, if a certificate or the profile is missing.
5. **Upload** with Transporter, or validate first with
   `xcrun altool --validate-app -f dist/appstore/Pastiche.pkg -t macos`.

`CFBundleVersion` comes from the git commit count and must increase with every
upload; the repository needs at least one commit for it to mean anything.

**If `security find-identity -v` does not list a certificate you just installed,**
check whether it is missing its intermediate. A new Apple certificate is issued by
the *WWDR G3* intermediate; a Mac that only has the old, expired 2013 WWDR
certificate cannot build the chain, and signing fails with
`errSecInternalComponent` or "unable to build chain to self-signed root". The fix
is to install the current intermediate from
<https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer>. Check that its
SHA-256 fingerprint is `DCF21878…AC91601F` before trusting it. The installer
certificate reports "Invalid Extended Key Usage" under the code-signing policy;
that is expected, since it is not a code-signing certificate.

**Not yet done for the store build:** the in-app onboarding for the manual
Accessibility grant described above. Today the popup's *Grant…* button opens the
right pane, but nothing tells a sandboxed user that they must add the app with
**+** themselves.

## Not included

By design: no sync, no clipboard stacks or queues, no snippet library, no
rich-text or file-URL history, no pinning. If you want those, Copy 'Em is
excellent and worth paying for.

## License

MIT — see [LICENSE](LICENSE).
