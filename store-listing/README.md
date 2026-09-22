# Store listing

Everything for the Mac App Store listing.

| Path | What |
| --- | --- |
| `en.md` | Every text field, with Apple's character limits. Paste each into App Store Connect. |
| `screenshots/` | Final 2880 x 1800 screenshots, without alpha. |
| `tools/capture.sh` | Regenerates the screenshots from the real app. |

## Regenerating screenshots

```sh
store-listing/tools/capture.sh
```

It opens the app's windows and takes focus for about a minute. Keystrokes typed
meanwhile go to those windows, so do not use the machine while it runs. It quits your
Pastiche first and relaunches it afterwards.

It runs a copy of the built app on a **demo history** made of invented text and three
generated images, so no real clipboard content appears. The app reads these
environment variables, which exist for this purpose and for tests:

| Variable | Effect |
| --- | --- |
| `PASTICHE_DATA_DIR` | Use another history folder |
| `PASTICHE_NO_CAPTURE=1` | Never record the real clipboard |
| `PASTICHE_FILTER` | Open the popup on `text` or `image` |
| `PASTICHE_QUERY` | Open the popup with this search |
| `PASTICHE_SETTINGS_TAB` | Open Settings on `general`, `privacy` or `about` |

## Before submitting

- The review notes in `en.md` describe enabling Accessibility by hand, because the
  system prompt does not appear in a sandboxed app. An in-app guide for this is not
  built yet.
- Check every screenshot by eye before uploading.
