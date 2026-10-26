// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
// Load the 3D showcase only near the viewport; keep the SVG as the still fallback.
export function setupLaptopScenes(root=document){
  for(const scene of root.querySelectorAll('[data-laptop-scene]')){
    const canvas=scene.querySelector('canvas'),fallback=scene.querySelector('img'),button=scene.querySelector('button')
    const motion=matchMedia('(prefers-reduced-motion: reduce)')
    let model,loading=false,failed=false,frame=0,previous=0,lastDraw=0,elapsed=0,visible=false,paused=false
    async function load(){
      if(model||loading||failed||motion.matches)return
      loading=true
      try{
        const {createLaptopModel}=await import('./laptop-model.js')
        model=createLaptopModel(canvas)
        resize();model.render(elapsed,0)
      }catch{failed=true}
      loading=false;refresh()
    }
    function tick(now){
      const delta=previous?Math.min((now-previous)/1000,.1):0
      elapsed+=delta;previous=now
      if(now-lastDraw>=1000/30){
        const pose=model.render(elapsed,(now-lastDraw)/1000)
        scene.dataset.pose=pose.map(value=>value.toFixed(1)).join(',')
        lastDraw=now
      }
      frame=requestAnimationFrame(tick)
    }
    function refresh(){
      cancelAnimationFrame(frame);previous=0;lastDraw=0
      const enabled=!!model&&!motion.matches&&!failed
      const running=enabled&&visible&&!document.hidden&&!paused
      canvas.hidden=!enabled;fallback.hidden=enabled;button.hidden=!enabled
      button.setAttribute('aria-label',paused?'Resume laptop rotation':'Pause laptop rotation')
      button.title=paused?'Resume motion':'Pause motion'
      button.querySelectorAll('[data-motion-icon]').forEach(icon=>icon.toggleAttribute('hidden',icon.dataset.motionIcon!==(paused?'play':'pause')))
      scene.dataset.state=!enabled?'still':running?'rotating':'paused'
      if(visible&&!model&&!failed&&!motion.matches)void load()
      if(running)frame=requestAnimationFrame(tick)
    }
    function resize(){model?.resize(scene.clientWidth,scene.clientHeight)}
    button.addEventListener('click',()=>{paused=!paused;refresh()})
    scene.addEventListener('pointermove',event=>{
      if(event.pointerType!=='mouse'||paused||motion.matches)return
      const box=scene.getBoundingClientRect()
      model?.pointer((event.clientX-box.left)/box.width*2-1,(event.clientY-box.top)/box.height*2-1)
    })
    scene.addEventListener('pointerleave',()=>model?.pointer(0,0))
    if(typeof IntersectionObserver==='function'){
      new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;refresh()},{threshold:0}).observe(scene)
    }else{visible=true;refresh()}
    if(typeof ResizeObserver==='function')new ResizeObserver(resize).observe(scene)
    else addEventListener('resize',resize)
    canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();failed=true;refresh()})
    document.addEventListener('visibilitychange',refresh)
    motion.addEventListener('change',refresh)
    addEventListener('pagehide',()=>{cancelAnimationFrame(frame);previous=0})
    addEventListener('pageshow',refresh)
  }
}
