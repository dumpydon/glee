// Copyright 2026 dumpydon. AGPL-3.0-only. All state is in this illustration only.
const one=s=>document.querySelector(s),all=s=>Array.from(document.querySelectorAll(s))
const query=new URLSearchParams(location.search)
if(query.has('hero'))document.documentElement.classList.add('hero')
let mode='timer',active=false,lid=false,seconds=7200,endsAt=0,timer
const hours=one('[aria-label="Hours"]'),minutes=one('[aria-label="Minutes"]')
function updateLid(){
  one('.switch').setAttribute('aria-checked',String(lid))
  one('.lid-status').textContent=lid?(active?'✓  Ready to close the lid':'◷  On for your next session'):'☾  Off'
  one('.lid-status').classList.toggle('ready',lid&&active)
  one('.lid-detail').textContent=lid?(active?'Stays awake within your battery and time limits.':'Start a session, then wait for Ready.'):'Your Mac sleeps when you close the lid.'
}
function setMode(next){
  mode=next
  all('[data-mode]').forEach(button=>{const selected=button.dataset.mode===mode;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1})
  for(const name of ['timer','until','unlimited'])one('#'+name+'-view').hidden=name!==mode
  validate()
}
all('[data-mode]').forEach((button,index,buttons)=>{
  button.addEventListener('click',()=>setMode(button.dataset.mode))
  button.addEventListener('keydown',event=>{if(['ArrowRight','ArrowLeft','Home','End'].includes(event.key)){event.preventDefault();const next=event.key==='Home'?0:event.key==='End'?2:(index+(event.key==='ArrowRight'?1:2))%3;setMode(buttons[next].dataset.mode);buttons[next].focus()}})
})
function requestedSeconds(){
  if(mode==='unlimited')return Infinity
  if(mode==='until'){
    const [h,m]=one('[type="time"]').value.split(':').map(Number)
    if(!Number.isFinite(h)||!Number.isFinite(m))return 0
    const date=new Date();date.setHours(h,m,0,0);if(date.getTime()<=Date.now())date.setDate(date.getDate()+1)
    return Math.ceil((date.getTime()-Date.now())/1000)
  }
  if(!hours.validity.valid||!minutes.validity.valid)return 0
  const value=Number(hours.value)*3600+Number(minutes.value)*60
  return value>0&&value<=86400?value:0
}
function validate(){one('#start').disabled=!requestedSeconds()}
all('.duration input,[type="time"]').forEach(input=>input.addEventListener('input',()=>{all('[data-minutes]').forEach(button=>button.classList.remove('selected'));validate()}))
all('[data-minutes]').forEach(button=>button.addEventListener('click',()=>{const value=Number(button.dataset.minutes);hours.value=Math.floor(value/60);minutes.value=value%60;all('[data-minutes]').forEach(b=>b.classList.toggle('selected',b===button));validate()}))
function paintTime(){
  if(!active)return
  seconds=mode==='unlimited'?Infinity:Math.max(0,Math.ceil((endsAt-Date.now())/1000))
  one('.countdown').textContent=seconds===Infinity?'∞':[Math.floor(seconds/3600),Math.floor(seconds/60)%60,seconds%60].map(v=>String(v).padStart(2,'0')).join(':')
  if(seconds===0)end()
}
function start(){seconds=requestedSeconds();if(!seconds)return;active=true;endsAt=Date.now()+seconds*1000;one('.setup-view').hidden=true;one('.active-view').hidden=false;one('#extend').hidden=mode==='unlimited';one('.ends-at').textContent=mode==='unlimited'?'Until you stop it':'Your Mac stays awake.';paintTime();updateLid();clearInterval(timer);timer=setInterval(paintTime,1000);one('.preview-note').textContent='Website preview · No system changes'}
function end(){active=false;clearInterval(timer);one('.setup-view').hidden=false;one('.active-view').hidden=true;updateLid()}
one('#start').addEventListener('click',start);one('#end').addEventListener('click',end)
one('#extend').addEventListener('click',()=>{endsAt=Math.min(endsAt+900000,Date.now()+86400000);paintTime()})
one('.switch').addEventListener('click',()=>{lid=!lid;updateLid();one('.preview-note').textContent=lid?'Illustration · The Mac app requires one-time helper setup.':'Website preview · No system changes'})
const now=new Date(Date.now()+7200000);one('[type="time"]').value=String(now.getHours()).padStart(2,'0')+':'+String(now.getMinutes()).padStart(2,'0')
validate();if(query.has('active')){lid=true;start()}
