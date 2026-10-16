// Checks the complete published file graph and release integrity before deployment.
import {readFile, readdir, stat} from 'node:fs/promises'
import {resolve, dirname} from 'node:path'
import {fileURLToPath} from 'node:url'
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'

const site=dirname(fileURLToPath(import.meta.url)),root=resolve(site,'../dist/site')
async function files(path){return (await Promise.all((await readdir(path,{withFileTypes:true})).map(entry=>entry.isDirectory()?files(resolve(path,entry.name)):resolve(path,entry.name)))).flat()}
const errors=[],pages=(await files(root)).filter(path=>path.endsWith('.html'))
async function exists(path){try{return (await stat(path)).isFile()}catch{return false}}
for(const path of pages){
  const html=await readFile(path,'utf8')
  if(/<!-- (SITE_NAV|SITE_FOOTER|DOWNLOAD_MENU) -->/.test(html))errors.push('Unexpanded component: '+path)
  if(/WakeBee|Apply Vigil|dumpydon\/vigil\//i.test(html))errors.push('Unadapted product content: '+path)
  const url=new URL(path.slice(root.length)||'/', 'https://glee.dumpydon.workers.dev')
  const baseMatch=html.match(/<base[^>]+href="([^"]+)"/),base=baseMatch?new URL(baseMatch[1],url):url
  for(const match of html.matchAll(/\b(?:src|href)="([^"]+)"/g)){
    const linked=new URL(match[1],base)
    if(linked.origin!==url.origin)continue
    let target=resolve(root,'.'+decodeURIComponent(linked.pathname))
    if(!await exists(target))target=resolve(target,'index.html')
    if(!await exists(target)){errors.push('Missing link '+match[1]+' in '+path);continue}
    if(linked.hash&&target.endsWith('.html')){
      const document=await readFile(target,'utf8'),id=decodeURIComponent(linked.hash.slice(1))
      if(!document.includes('id="'+id+'"'))errors.push('Missing anchor '+linked.hash+' in '+target)
    }
  }
}
for(const path of (await files(resolve(site,'download'))).filter(p=>p.endsWith('.js')))execFileSync(process.execPath,['--check',path])
execFileSync(process.execPath,['--check',resolve(site,'worker.js')])
const release=JSON.parse(await readFile(resolve(site,'download/release.json'),'utf8'))
if(!release.dmg.startsWith('https://github.com/dumpydon/glee/releases/download/'))errors.push('Unexpected download destination')
const video=await readFile(resolve(root,'download/assets/glee-launch.mp4'))
if(createHash('sha256').update(video).digest('hex')!=='facd89a7e49ba1aeed09cbd916d0726e108b7c4988e067f7776741283493e625')errors.push('Launch film differs from the approved version')
if(errors.length)throw new Error(errors.join('\n'))
console.log('Checked '+pages.length+' pages: local links, anchors, assets, script syntax, release destination, and approved video integrity.')
