// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
// Presentation only: no analytics, accounts, persistence, or Mac power access.
import {setupFilmPlayers} from './film-player.js'
const one=(s,r=document)=>r.querySelector(s)
const all=(s,r=document)=>Array.from(r.querySelectorAll(s))
const motion=matchMedia('(prefers-reduced-motion: reduce)')
setupFilmPlayers()
const nav=one('.navtoggle'),navMenu=one('#navmenu')
function navClose(){navMenu?.classList.remove('on');nav?.setAttribute('aria-expanded','false')}
nav?.addEventListener('click',()=>{const open=navMenu.classList.toggle('on');nav.setAttribute('aria-expanded',String(open))})
all('a',navMenu||document.createElement('div')).forEach(a=>a.addEventListener('click',navClose))
function menusClose(){all('.dlgrp').forEach(g=>{g.classList.remove('open');one('.dlbtn',g).setAttribute('aria-expanded','false');one('.dlmenu',g).inert=true})}
all('.dlgrp').forEach(group=>{
  const button=one('.dlbtn',group),menu=one('.dlmenu',group)
  menu.inert=true
  function open(){menusClose();group.classList.add('open');button.setAttribute('aria-expanded','true');menu.inert=false}
  button.addEventListener('click',()=>group.classList.contains('open')?menusClose():open())
  button.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){e.preventDefault();open();one('[role="menuitem"]',group).focus()}})
  all('[role="menuitem"]',group).forEach((link,index,links)=>link.addEventListener('keydown',e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();links[(index+(e.key==='ArrowDown'?1:links.length-1))%links.length].focus()}}))
})
document.addEventListener('click',e=>{if(!e.target.closest('.dlgrp'))menusClose();if(!e.target.closest('nav'))navClose()})
let toastTimer
const toast=one('#dltoast')
function hideToast(){toast?.classList.remove('on');toast?.setAttribute('aria-hidden','true');if(toast)toast.inert=true;clearTimeout(toastTimer)}
all('[data-download]').forEach(link=>link.addEventListener('click',()=>{menusClose();navClose();if(!toast)return;toast.classList.add('on');toast.inert=false;toast.setAttribute('aria-hidden','false');clearTimeout(toastTimer);toastTimer=setTimeout(hideToast,16000)}))
one('#dltx')?.addEventListener('click',hideToast)
const modal=one('.video-modal')
all('[data-tour]').forEach(link=>link.addEventListener('click',e=>{if(!modal||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;e.preventDefault();all('video').forEach(video=>video.pause());modal.showModal();document.body.style.overflow='hidden';one('.modal-close',modal).focus()}))
function closeTour(){if(!modal?.open)return;modal.close()}
one('.modal-close',modal||document.createElement('div'))?.addEventListener('click',closeTour)
modal?.addEventListener('click',e=>{if(e.target===modal){const r=modal.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)closeTour()}})
modal?.addEventListener('close',()=>{one('video',modal).pause();document.body.style.overflow=''})
addEventListener('keydown',e=>{if(e.key==='Escape'){const active=all('.dlgrp.open')[0];if(active)one('.dlbtn',active).focus();menusClose();navClose();hideToast()}})
// A single reveal per section, with immediate content for reduced motion.
if(!motion.matches&&typeof IntersectionObserver==='function'){
  const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('in');observer.unobserve(entry.target)}}),{threshold:.12})
  all('.io').forEach(el=>{el.classList.add('reveal');observer.observe(el)})
}else all('.io').forEach(el=>el.classList.add('in'))
motion.addEventListener('change',()=>{if(motion.matches)all('.io').forEach(el=>el.classList.add('in'))})
// Iframes keep the app illustration's original proportions on every screen.
function fitSnaps(){all('.snap').forEach(wrapper=>{
  const frame=one('iframe',wrapper);if(!frame)return
  const width=Number(frame.dataset.w),height=Number(frame.dataset.h)
  if(!width||!height)return
  const available=wrapper.parentElement.clientWidth||width,scale=Math.min(1,available/width)
  wrapper.style.width=width*scale+'px';wrapper.style.height=height*scale+'px';frame.style.width=width+'px';frame.style.height=height+'px';frame.style.transform='scale('+scale+')'
})}
all('.snap iframe').forEach(frame=>frame.addEventListener('load',fitSnaps));fitSnaps()
if(typeof ResizeObserver==='function')new ResizeObserver(fitSnaps).observe(document.body)
addEventListener('resize',fitSnaps)
addEventListener('message',event=>{
  if(event.origin!==location.origin||!event.data?.gleeInstallGuide)return
  const frame=all('[data-install-walkthrough]').find(f=>f.contentWindow===event.source)
  if(!frame)return
  const height=event.data.gleeInstallGuide.height
  if(Number.isFinite(height)&&height>=200&&height<=1600)frame.style.height=Math.ceil(height)+'px'
})
// Release labels are local metadata; downloads remain usable without JavaScript.
fetch('release.json').then(r=>r.ok?r.json():null).then(release=>{if(!release)return;all('[data-version]').forEach(el=>el.textContent=release.version)}).catch(()=>{})
