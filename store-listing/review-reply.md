<!-- Reply to App Review, Guideline 2.1 - Information Needed (1.1.0 build 5).
     Paste the text below the line into the Resolution Center reply, attach the
     recording, and paste the same text into App Review Information > Notes. -->

## Recording plan

Install build 5 from TestFlight (it replaces the Homebrew copy in /Applications), then run
`store-listing/tools/recording.sh prep`. It empties the history, resets Accessibility and
opens the demo files. Pastiche needs no permission in this flow, so the recording shows none being requested. Record with ⌘⇧5 (Record Entire Screen). Keep it under 3 minutes.
Afterwards run `recording.sh restore`, `recording.sh shrink <file.mov>` if the file is large,
and reinstall the Homebrew build (`brew reinstall --cask pastiche`).

1. Show Finder > Applications, double-click Pastiche. The menu bar icon appears.
2. In TextEdit (Notes.txt), select and copy each of the three lines, one at a time.
3. In Preview (Sunset.png), Edit > Select All, then ⌘C.
4. Press ⌘'. The popup lists the text items and the image.
5. Arrow up and down. Press → to show Text, → to show Images, ← ← back to All.
6. Type "lunch": the list filters. Press Esc to clear.
7. In TextEdit, click below "Pasted from Pastiche:", press ⌘', select an item, press Return, then press ⌘V. The item is pasted. No permission dialog appears.
8. Optional, only if showing auto-paste: Settings (⌘,) > Shortcuts > turn on "Paste into the active app automatically". macOS asks for Accessibility; grant it. Return now pastes without pressing ⌘V.
9. Press ⌘', select an item, press ⌫. It is removed.
10. Menu bar icon > Quit.

---

Thank you for the review. Answers to each point follow. A screen recording is attached.

1. Screen recording
The attached recording was made on a Mac running the latest macOS. It starts with launching Pastiche from the Applications folder and shows copying text and an image, opening the history with ⌘', filtering by type, searching, pasting an item into TextEdit with ⌘V, and deleting an item. No permission is requested at any point.
The app has no account registration or login, no user-generated content shared with other users, and no paid content or In-App Purchase.

2. Purpose and target audience
Pastiche is a clipboard manager for macOS. macOS keeps only the last thing you copied; Pastiche keeps a history of copied text and images so you can paste an earlier item again. It is aimed at anyone who copies and pastes often on a Mac: developers, writers, support staff, office users. The value is speed: press a shortcut, pick an item with the arrow keys, press Return to paste it. It is free and open source (MIT licence): https://github.com/bcollard/pastiche

3. Setup and main features
No login, account or sample file is needed.
- Launch Pastiche. It is a menu bar app: a clipboard icon appears in the menu bar. There is no Dock icon and no main window.
- Copy some text and an image in any app.
- Press ⌘' to open the history. Use the arrow keys to select an item, ← → to filter by All, Text or Images, and type to search.
- Press Return to copy the selected item to the clipboard and return to the app that was in front. Press ⌘V to paste it.
- Pastiche asks for no permission by default. There is one optional setting, Settings (⌘, in the popup, or the menu bar icon > Settings) > Shortcuts > "Paste into the active app automatically", which is off by default. Turning it on makes Pastiche send ⌘V for you, which macOS allows only with the Accessibility permission, so macOS then asks for it. Everything else works without it.

4. External services
None. Pastiche uses no external service, server, SDK, authentication provider, payment processor, analytics or AI service. It has no network access. It uses only Apple system frameworks (AppKit, SwiftUI and, only if the optional auto-paste setting is on, the macOS Accessibility API). Clipboard history is stored locally in the app container.

5. Regional differences
None. The app works the same in all regions. It does not depend on location or on any online content.

6. Regulated industry or third-party material
Not applicable. The app does not operate in a regulated industry and contains no third-party protected material. All code and artwork are our own and published under the MIT licence.
