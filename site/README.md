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

```sh
npm run check
npm run deploy
```

Wrangler uses the operator's existing Cloudflare login. No credentials belong in this repository. The Worker has no database, forms, analytics, cookies, or account system. Release metadata is kept in `download/release.json`; update its version and URLs when publishing a new app release.

The interactive app panels are website illustrations. They do not change power settings or install software. The first-launch instructions follow [Apple's guidance](https://support.apple.com/en-us/102445). The app remains locally signed and is not Apple-notarized.

Layout and first-launch player adapted with the owner's authorization from [dumpydon/vigil](https://github.com/dumpydon/vigil). Copyright © 2026 dumpydon. AGPL-3.0-only; see the root LICENSE and NOTICE.
