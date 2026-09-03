# site: vanthlabs.org

The site of Vanth Labs, the company behind Hannah. Plain HTML/CSS/JS, **no build step, no
dependencies**. Live at **https://vanthlabs.org/**.

## Pages

| Path | What it is |
|---|---|
| `/` (`index.html`) | Hannah: the product landing, with the copyable install command, capabilities, requirements, FAQ |
| `/about/` | Vanth Labs: what we believe, who we are, work with us, contact |
| `/brand/` | Brand and press kit: logos, colors, type, naming, official paragraph, screenshots |
| `404.html` | Custom not-found page (GitHub Pages picks it up by name) |

## Files

| File | What it is |
|---|---|
| `styles.css` | One stylesheet for every page: dark theme, violet accent, Fraunces + Inter |
| `main.js` | Landing only: OS switcher, copy button, hero video behavior |
| `install.sh`, `install-mac.sh`, `install.ps1` | The installers, served from the root (their URLs are in every README: do not move them) |
| `assets/vanth-*.svg`, `assets/vanth-*.png` | The wordmark (Fraunces outlines with the wing attached to the V) and the mark, in violet, white and black; PNGs for avatars; `og-vanth.png` for link previews |
| `assets/*.webp` | Screenshots; each has its JPG next to it as the fallback in a `<picture>` |
| `assets/fonts/` | Fraunces and Inter, latin subsets, self-hosted and preloaded (OFL) |
| `favicon.svg` | The mark on a violet tile |
| `robots.txt`, `sitemap.xml`, `llms.txt` | Crawlers: everything allowed (AI crawlers named explicitly), the three pages, a plain-text summary |
| `CNAME`, `.nojekyll` | Custom domain; serve files as-is |

## Logo

The wordmark is generated, not drawn by hand: "Vanth Labs" set in Fraunces (wght 500, opsz 48)
converted to outlines with fontTools, plus the wing (the mark, unchanged) scaled to the cap height
and attached at the left of the V, its top feather flush with the cap line and the light on the
baseline. Regenerate only if the wing or the type changes; otherwise edit nothing by hand.

## SEO

Every page has its own title, description, canonical, OpenGraph and Twitter cards, and JSON-LD:
`Organization`, `WebSite`, `SoftwareApplication` and `FAQPage` on the landing; `Organization`
(with founders and contact points), `Person`, `AboutPage` and `BreadcrumbList` on About;
`WebPage` and `BreadcrumbList` on Brand. Lighthouse 12 on the live site (2026-09-03), desktop and
mobile, all three pages: 100 performance, 100 accessibility, 100 best practices, 100 SEO.

## Preview locally

```bash
cd hannah-site && python3 -m http.server 8080
```

## Deploy

GitHub Pages serves the root of `main` automatically, push and it's live.
(Enabled once via Settings → Pages → Deploy from branch → `main` / `/root`.)

## How install.sh works

Queries the GitHub API for the latest release of [`Vanth-Labs/desktop`](https://github.com/Vanth-Labs/desktop),
downloads the first `*.AppImage` asset into `~/.local/bin/Hannah.AppImage` and makes it
executable. It refuses gracefully when no release exists yet.

**It only works once a real release is published**: tagging `v*` in `hannah-desktop`
triggers its CI workflow, which builds and uploads the artifacts.

## If anything moves

- Pages URL changes → update the command in `index.html` (hero), `og:url`, and `SITE` in `install.sh`.
- Release asset name changes → nothing to change here (the script picks any `*.AppImage`).
- New OS builds ship → enable the disabled tabs in `index.html` and extend `install.sh`.
