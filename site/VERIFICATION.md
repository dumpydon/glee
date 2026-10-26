# Download site verification

Checked October 16, 2026.

- The build validates all 15 generated HTML pages, local links and anchors, referenced assets, JavaScript syntax, and the release destination.
- Chrome desktop review covered the green glass navigation, page sections, download menu, launch-film dialog, first-launch guide, FAQ, and footer.
- Browser-rendered frames at 320, 390, and 768 CSS pixels checked phone and tablet layouts. The mobile hero stays inside its column; the navigation drawer opens; the embedded first-launch player resizes to its content without horizontal overflow.
- The session illustration was exercised in Timer, Until, and Unlimited modes. A five-minute timer extended to twenty minutes. Start, end, and the illustrative closed-lid switch worked.
- All five first-launch chapters were checked. The embedded warning and Privacy & Security steps rendered with Glee branding and usable playback and chapter controls.
- The launch MP4 played to its 19-second end without a media error. The built MP4 has the same SHA-256 as the approved source video; it has no added splash effect.
- A download initiated from the page produced the actual universal DMG. Its SHA-256 matched `587baa5544489f0c0cd15b793e39f0c8ad514706011ff59ce8e278d562096132`.
- The download menu was operated with ArrowDown and Escape. FAQ details opened normally. Native dialog controls close the film and stop playback.
- Reduced-motion CSS disables animation; the guide does not auto-play when reduced motion is requested. Written installation steps and direct download links remain available without JavaScript.
- Wrangler's deployment dry run bundled the Worker successfully. The site uses only a static-assets binding, with no database or secrets.

These checks concern the website. The app release and installed Mac app were not rebuilt or replaced for this work. The web app panels are illustrations and do not prevent sleep or install helpers.

## Opening layout and launch-film controls

- The landing page opens with the introduction and download buttons, followed immediately by closed-lid mode and the 19-second launch film.
- The landing-page privacy feature and the Three ways to stay awake feature were removed.
- The page, tour, and popup share one launch-film player. Its charcoal circular controls provide restart and play/pause using actual media events. Native controls remain the fallback without JavaScript.
- Browser checks covered playback, keyboard pause, sound, reaching the film's end, and replay from the beginning without a media error. The MP4's approved checksum remains unchanged.
- Phone and tablet frames at 320, 390, and 768 CSS pixels were reviewed. The mobile play/pause button has a 44-pixel touch target and stays inside the video frame.

## Replay and automatic playback

Checked October 17, 2026 on the local site in Chrome.

- A separate restart button sits immediately left of play/pause. Restarting after the film ended reset playback from 19 seconds to the beginning and resumed it without a media error.
- The film stayed paused before reaching it, played muted upon entering view, paused after scrolling to FAQ, and resumed upon returning. A manual pause stayed paused while in view; a fresh mouse hover resumed playback.
- Opening the tour popup played its film and paused the background film. Closing the popup stopped its playback.
- At a 390-pixel viewport, both restart and play/pause had 44-pixel touch targets, stayed inside the film, and caused no horizontal page overflow. The temporary viewport override was reset after testing.
- No browser warnings or errors were recorded during these checks. The build still validates all 15 generated pages and the approved MP4 checksum.
- Automatic playback respects reduced-motion preferences. The play button remains available if a browser blocks autoplay; sound is optional through the unmute control.

These checks used localhost. Cloudflare deployment was not checked or awaited for this change.

## Closed-laptop illustration

Checked October 26, 2026 on the local site in Chrome.

- Replaced the separately transformed CSS lid and base with a single SVG. The flat lid, rim, seam, and base follow the same outline and perspective.
- Reviewed the closed-lid section at desktop size and phone viewports measuring 320 and 391 CSS pixels. The image loaded, the status card stayed below the laptop, and neither phone viewport had horizontal page overflow.
- The illustration scales in the document flow without a fixed scene height. Temporary viewport overrides were reset after testing.
- All 15 generated pages, local assets, scripts, release links, and the approved video checksum passed `npm run check`.

## Rotating closed MacBook

Checked October 26, 2026 on the local site in Chrome.

- The closed chassis makes one smooth turn every 24 seconds. Its lid, seam, base, and engraving share a projection; the Glee artwork stays centered above it.
- Observed changing angles across the turn, paused the model at 135 degrees, and confirmed it stayed still until Resume. Scrolling to FAQ stopped rendering; returning resumed from the same angle.
- The 320-CSS-pixel phone layout had no horizontal overflow. Its pause/resume button measured 44 pixels, and the model stayed above the status card.
- The renderer uses no additional libraries, stops when offscreen or the document is hidden, and retains the approved static SVG for reduced-motion preferences or unavailable JavaScript/canvas.
