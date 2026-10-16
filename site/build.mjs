// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
import {cp, mkdir, rm, writeFile, readFile, readdir} from 'node:fs/promises'
import {fileURLToPath} from 'node:url'
import {resolve, dirname} from 'node:path'

const site = dirname(fileURLToPath(import.meta.url))
const output = resolve(site, '../dist/site')
await rm(output, {recursive:true, force:true})
await mkdir(output, {recursive:true})
await cp(resolve(site,'download'), resolve(output,'download'), {recursive:true})
const snippets = Object.fromEntries(await Promise.all(['nav','footer','download-menu'].map(async name=>[name,await readFile(resolve(site,`download/${name}.html`),'utf8')])))
for (const entry of await readdir(resolve(output,'download'))) {
  if (!entry.endsWith('.html') || ['nav.html','footer.html','download-menu.html'].includes(entry)) continue
  const path = resolve(output,'download',entry)
  const html = (await readFile(path,'utf8'))
    .replaceAll('<!-- SITE_NAV -->',snippets.nav)
    .replaceAll('<!-- SITE_FOOTER -->',snippets.footer)
    .replaceAll('<!-- DOWNLOAD_MENU -->',snippets['download-menu'])
  await writeFile(path,html)
}
await cp(resolve(output,'download/index.html'), resolve(output,'index.html'))
await cp(resolve(output,'download/404.html'), resolve(output,'404.html'))
for (const route of ['install','privacy','changelog','first-launch','tour']) {
  await mkdir(resolve(output,route), {recursive:true})
  await cp(resolve(output,`download/${route}.html`), resolve(output,`${route}/index.html`))
}
for (const name of ['nav','footer','download-menu']) await rm(resolve(output,`download/${name}.html`))
const assets = resolve(output,'download/assets')
await mkdir(assets, {recursive:true})
for (const [source,target] of [
  ['docs/branding/thumbnail-256.png','app-icon.png'],
  ['docs/branding/thumbnail-128.png','app-icon-128.png'],
  ['docs/branding/menu-white-96.png','menu-white.png'],
  ['docs/media/glee-launch.mp4','glee-launch.mp4'],
  ['docs/media/glee-launch-poster.jpg','glee-launch-poster.jpg'],
]) await cp(resolve(site,'..',source), resolve(assets,target))
await writeFile(resolve(output,'robots.txt'), 'User-agent: *\nAllow: /\nSitemap: https://glee.dumpydon.workers.dev/sitemap.xml\n')
await writeFile(resolve(output,'sitemap.xml'), '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+['','install/','privacy/','changelog/','first-launch/','tour/'].map(route=>`<url><loc>https://glee.dumpydon.workers.dev/${route}</loc></url>`).join('')+'</urlset>\n')
console.log('Built Glee download site in dist/site (including original, approved launch video).')
