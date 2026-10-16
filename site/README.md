# Glee download website

Public URL: https://glee.dumpydon.workers.dev/

## Design and delivery plan

1. Preserve the owner-authorized Vigil download page's floating glass navigation, typography, section rhythm, interactive first-launch player, and atmospheric footer.
2. Apply Glee's green liquid and UFO identity over a black background. Use the existing Glee artwork, white menu symbol, and approved 19-second launch video.
3. Explain the actual Mac app: Timer, Until, Unlimited, optional closed-lid setup, battery limits, display controls, and local preferences. Link the universal macOS 14+ release directly. No payment or sign-in.
4. Adapt the 15-second first-launch walkthrough to Glee. Keep the illustrated warning distinct from the separate administrator-approved closed-lid helper setup.
5. Check desktop and mobile layouts, keyboard controls, reduced motion, downloads, video playback, and all public routes. Publish the `glee` Worker to the existing Cloudflare account.

## Work on the website

```sh
cd site
npm ci
npm run dev
```

`download/` contains the editable HTML, CSS, and JavaScript. `build.mjs` copies these pages and the canonical app artwork and launch video into `../dist/site/`. The preview uses the same Worker and static asset routing as production.

## Automatic deployment

Cloudflare Workers Builds is connected to `dumpydon/glee`. Every push to `main` automatically builds, checks, and publishes the website to https://glee.dumpydon.workers.dev/.

| Cloudflare setting | Value |
| --- | --- |
| Production branch | `main` |
| Root directory | `site` |
| Build command | `npm ci && npm run check` |
| Deploy command | `npx wrangler deploy` |
| Build watch paths | Include `*`; no exclusions |
| Builds | Enabled |
| Preview builds | Disabled |

Commit and push website changes to `main`; Cloudflare runs the deployment without a separate local publishing step. A failed build or check does not publish a new website version. Review the build result under **Cloudflare → Workers & Pages → glee → Deployments**.

This pipeline publishes the website. Mac app builds and downloadable app releases use their own release workflow. Update the website's download links and release metadata when a new app release is published.

For a manual recovery deployment, the existing commands remain available:

```sh
npm run check
npm run deploy
```

Cloudflare uses its existing GitHub connection and managed build token. Manual Wrangler commands use the operator's Cloudflare login. No credentials belong in this repository. The Worker has no database, forms, analytics, cookies, or account system. Release metadata is kept in `download/release.json`; keep it and the download links in the HTML templates in sync when publishing a new app release.

The interactive app panels are website illustrations. They do not change power settings or install software. The first-launch instructions follow [Apple's guidance](https://support.apple.com/en-us/102445). The app remains locally signed and is not Apple-notarized.

Layout and first-launch player adapted with the owner's authorization from [dumpydon/vigil](https://github.com/dumpydon/vigil). Copyright © 2026 dumpydon. AGPL-3.0-only; see the root LICENSE and NOTICE.
