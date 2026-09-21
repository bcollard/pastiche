# Pastiche website

Static marketing site for the app. Hand-rolled HTML, CSS and one small script:
no build step, no framework, no third-party requests. It follows the conventions
of the other sites (`claudestatus.runlocal.dev`, `headsmith`,
`chrome-advanced-bookmarks`): one page, `privacy.html`, `robots.txt`,
`sitemap.xml`, automatic dark mode.

```
website/
├── index.html        the page
├── privacy.html      privacy policy (App Store Connect asks for a URL)
├── 404.html          uses root-absolute paths on purpose
├── styles.css        design tokens + everything else
├── app.js            theme toggle, copy buttons, hero demo
├── robots.txt  sitemap.xml
├── assets/           favicon.svg, icon.png, apple-touch-icon.png, og-image.png
└── scripts/make_og.swift   regenerates assets/og-image.png
```

## Preview

```sh
cd website && python3 -m http.server 8765
# http://localhost:8765/
```

## Before publishing

These are placeholders, chosen to match the other sites. Check each one.

| What | Where | Current value |
| --- | --- | --- |
| Product name | everywhere | `Pastiche` |
| Site URL | `<link rel=canonical>`, `og:*`, `twitter:*`, `sitemap.xml`, `robots.txt`, `privacy.html` | `https://pastiche.runlocal.dev/` |
| Repository | links in `index.html`, `privacy.html` | `github.com/bcollard/pastiche` (created private; make it public before launch) |
| Download | *Install* section | build-from-source only; the copy says signed builds will be on the releases page |
| App path in the `otool` example | *Check it yourself* | `/Applications/Pastiche.app` |

To rename or move the site in one go:

```sh
sed -i '' 's/Pastiche/NewName/g; s#pastiche.runlocal.dev#newname.example#g' \
  index.html privacy.html 404.html sitemap.xml robots.txt
swift scripts/make_og.swift assets/icon.png assets/og-image.png   # after editing the title in it
```

The app is already named to match (`BUNDLE_NAME` and `BUNDLE_ID` in the `Makefile`,
`Info.plist`, menu strings, `README.md`). If you ever rename again, do it **before**
registering the App ID: a bundle ID cannot be changed once an App Store Connect
record exists.

## Deploying

`.github/workflows/deploy-website.yaml` publishes `website/` to
<https://pastiche.runlocal.dev/> on every push to `main` that touches the site,
which includes a merged pull request. It can also be run by hand from the Actions
tab.

```
push / merge to main  ->  Actions  ->  gs://pastiche-runlocal-dev  ->  load balancer + Cloud CDN  ->  pastiche.runlocal.dev
```

It authenticates with Workload Identity Federation (no stored keys), mirrors the
folder with `gsutil rsync -d`, then sets `Cache-Control`. `README.md` and
`scripts/` stay out of the bucket. Two guards worth knowing about: a run refuses to
mirror if a core file is missing (`-d` deletes whatever is not in the source, so an
empty checkout would wipe the site), and only one deploy runs at a time.

**Freshness.** The bucket is behind Cloud CDN, which honours `Cache-Control`. HTML,
CSS, JS, `robots.txt` and `sitemap.xml` are cached for 10 minutes and images for a
day, so a change can take up to ten minutes to appear. Purging the CDN on demand
would need the `compute.urlMaps.invalidateCache` permission, which the deploy
service account does not have.

### One-time setup

The workflow cannot authenticate until this exists. Nothing here has been run yet.

| Piece | Where | State on 2026-09-21 |
| --- | --- | --- |
| Bucket `pastiche-runlocal-dev` (public read, index + 404) | GCP, `personal-218506` | exists, already holds the site |
| Shared WIF pool/provider, `claudecodebucketadmin` role | GCP | exist |
| **Service account `gha-push-gcs-pastiche` + repo binding** | `cicd/setup-gcp-wif.sh` | **missing: run the script** |
| Load balancer host rule, backend bucket (Cloud CDN on) | `gcp-load-balancer-bco` | applied |
| DNS A record `pastiche.runlocal.dev` -> `35.227.220.156` | Cloud DNS zone `runlocal-dev` (not managed by the Terraform repo) | in place |
| Managed TLS certificate | `gcp-load-balancer-bco` | `PROVISIONING`; HTTPS will not answer until it is `ACTIVE` (10-60 min) |

```sh
./cicd/setup-gcp-wif.sh        # idempotent; uses the `perso` gcloud config for this run only
```

The script shows the active gcloud account and asks for confirmation before it changes
anything. It lives outside `website/` so it is never published.

### Checking it

```sh
# What would a deploy change? Read-only; prints "Would copy/remove" lines.
CLOUDSDK_ACTIVE_CONFIG_NAME=perso gsutil -m rsync -n -r -d \
  -x '^README\.md$|^scripts/.*|^cicd/.*|(^|/)\.DS_Store$|(^|/)gha-creds-.*\.json$' \
  website gs://pastiche-runlocal-dev

curl -sI https://pastiche.runlocal.dev/ | head -1     # once DNS and the certificate are live
```

On the other hosting route, GitHub Pages, the page links are relative, so the site
also works from `https://<user>.github.io/<repo>/`. Only `404.html` needs a domain
root.

## Deliberately left out

- **Analytics.** The `claudestatus` page loads Google Analytics. This one does
  not: the app's pitch is that nothing leaves your Mac, and `privacy.html` says
  the site sets no cookies and loads no third-party scripts. Adding tracking would
  make that page untrue, so update it if you ever do.
- **Screenshots.** The hero is an HTML illustration of the real popup, driven by
  `app.js`, rather than a screenshot. It follows light and dark mode and contains
  no real clipboard data. Swap in real captures if you prefer; do not use a capture
  of a real history.
