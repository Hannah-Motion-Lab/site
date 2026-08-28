# hannah-site: landing page

One-page site for Hannah, Ollama-style: hero with the copyable install command,
feature grid, requirements and links to every repo in the org. Plain HTML/CSS/JS , 
**no build step, no dependencies, no webfonts**.

Live at **https://hannah-motion-lab.github.io/site/**

## Files

| File | What it is |
|---|---|
| `index.html` | The whole page (single section flow: hero → features → requirements → source) |
| `styles.css` | Dark theme, violet→pink accent, system font stacks |
| `main.js` | Just the Copy button (clipboard API + legacy fallback) |
| `install.sh` | Ollama-style installer served from this same page |
| `.nojekyll` | Tells GitHub Pages to serve files as-is |

## Preview locally

```bash
cd hannah-site && python3 -m http.server 8080
```

## Deploy

GitHub Pages serves the root of `main` automatically, push and it's live.
(Enabled once via Settings → Pages → Deploy from branch → `main` / `/root`.)

## How install.sh works

Queries the GitHub API for the latest release of [`Hannah-Motion-Lab/desktop`](https://github.com/Hannah-Motion-Lab/desktop),
downloads the first `*.AppImage` asset into `~/.local/bin/Hannah.AppImage` and makes it
executable. It refuses gracefully when no release exists yet.

**It only works once a real release is published**: tagging `v*` in `hannah-desktop`
triggers its CI workflow, which builds and uploads the artifacts.

## If anything moves

- Pages URL changes → update the command in `index.html` (hero), `og:url`, and `SITE` in `install.sh`.
- Release asset name changes → nothing to change here (the script picks any `*.AppImage`).
- New OS builds ship → enable the disabled tabs in `index.html` and extend `install.sh`.
