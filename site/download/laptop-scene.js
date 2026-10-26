// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
// Project a rigid rounded chassis: the lid, seam, and base turn together.
const revolution=24000,turn=Math.PI*2
const outline=[]
for(const [x,z,start] of [[-474,-299,180],[474,-299,270],[474,299,0],[-474,299,90]]){
  for(let step=0;step<=10;step++){
    const angle=(start+step*9)*Math.PI/180
    outline.push([x+Math.cos(angle)*26,z+Math.sin(angle)*26])
  }
}

export function setupLaptopScenes(root=document){
  for(const scene of root.querySelectorAll('[data-laptop-scene]')){
    const canvas=scene.querySelector('canvas'),fallback=scene.querySelector('img'),button=scene.querySelector('button')
    const ctx=canvas.getContext('2d')
    if(!ctx)continue
    const motion=matchMedia('(prefers-reduced-motion: reduce)')
    let angle=0,frame=0,previous=0,lastDraw=0,visible=false,paused=false

    function path(points,offset=0,close=true){
      ctx.beginPath();ctx.moveTo(points[0][0],points[0][1]+offset)
      for(const [x,y] of points.slice(1))ctx.lineTo(x,y+offset)
      if(close)ctx.closePath()
    }
    function draw(){
      const cos=Math.cos(angle),sin=Math.sin(angle)
      // The initial projection matches the approved still illustration.
      const a=.64*cos-.507692*sin,b=.13*cos+.315385*sin
      const c=-.64*sin-.507692*cos,d=-.13*sin+.315385*cos
      const project=([x,z])=>[600+a*x+c*z,235+b*x+d*z]
      const points=outline.map(project)
      const left=points.reduce((best,p,i)=>p[0]<points[best][0]?i:best,0)
      const right=points.reduce((best,p,i)=>p[0]>points[best][0]?i:best,0)
      const front=[]
      for(let i=right;;i=(i+1)%points.length){front.push(points[i]);if(i===left)break}
      const scale=canvas.width/1200
      ctx.setTransform(scale,0,0,scale,0,0);ctx.clearRect(0,0,1200,480)

      ctx.save();ctx.translate(600,441);ctx.scale(1,.075)
      const shadow=ctx.createRadialGradient(0,0,20,0,0,475)
      shadow.addColorStop(0,'#000a');shadow.addColorStop(1,'#0000')
      ctx.fillStyle=shadow;ctx.fillRect(-500,-500,1000,1000);ctx.restore()

      path(points,22);ctx.fillStyle='#151a16';ctx.fill();ctx.strokeStyle='#080c09';ctx.lineWidth=2;ctx.stroke()
      path([...front,...front.map(([x,y])=>[x,y+22]).reverse()])
      const edge=ctx.createLinearGradient(110,260,1090,380)
      edge.addColorStop(0,'#464d44');edge.addColorStop(.48,'#2d332e');edge.addColorStop(1,'#151a17')
      ctx.fillStyle=edge;ctx.fill()
      path(front,8,false);ctx.strokeStyle='#090e0a';ctx.lineWidth=3;ctx.stroke()
      path(front,18,false);ctx.strokeStyle='#95a18d30';ctx.lineWidth=1.4;ctx.stroke()

      path(points)
      const aluminum=ctx.createLinearGradient(329,76,856,391)
      aluminum.addColorStop(0,'#60665f');aluminum.addColorStop(.4,'#393e3a');aluminum.addColorStop(1,'#222724')
      ctx.fillStyle=aluminum;ctx.fill();ctx.strokeStyle='#b5c5a766';ctx.lineWidth=1.6;ctx.stroke()

      // The engraving stays on the lid plane rather than sliding over the model.
      ctx.save();ctx.transform(a,b,c,d,600,235);ctx.fillStyle='#1a211ba6'
      ctx.beginPath();ctx.ellipse(0,-21,48,13,0,0,turn);ctx.fill()
      ctx.beginPath();ctx.ellipse(0,-24,26,32,0,Math.PI,turn);ctx.fill()
      ctx.beginPath();ctx.moveTo(-14,-6);ctx.lineTo(0,6);ctx.lineTo(14,-6);ctx.fill();ctx.restore()
      if(d>0){
        const notch=[project([-75,325]),project([75,325])]
        path([notch[0],notch[1],[notch[1][0]-4,notch[1][1]+5],[notch[0][0]+4,notch[0][1]+5]])
        ctx.fillStyle='#101610';ctx.fill()
      }
      canvas.dataset.angle=String(Math.round(angle*180/Math.PI)%360)
    }
    function tick(now){
      if(previous)angle=(angle+(now-previous)*turn/revolution)%turn
      previous=now
      // A calm turntable needs only 30 frames per second.
      if(now-lastDraw>=1000/30){draw();lastDraw=now}
      frame=requestAnimationFrame(tick)
    }
    function refresh(){
      cancelAnimationFrame(frame);previous=0
      const still=motion.matches,running=visible&&!document.hidden&&!paused&&!still
      canvas.hidden=still;fallback.hidden=!still;button.hidden=still
      button.setAttribute('aria-label',paused?'Resume laptop rotation':'Pause laptop rotation')
      button.title=paused?'Resume rotation':'Pause rotation'
      button.querySelectorAll('[data-motion-icon]').forEach(icon=>icon.toggleAttribute('hidden',icon.dataset.motionIcon!==(paused?'play':'pause')))
      scene.dataset.state=still?'still':running?'rotating':'paused'
      if(running)frame=requestAnimationFrame(tick)
    }
    function resize(){
      const density=Math.max(1,Math.min(devicePixelRatio||1,2))
      const pixels=Math.max(1,Math.round(scene.clientWidth*density))
      canvas.width=pixels;canvas.height=Math.round(pixels*.4);draw()
    }
    resize();refresh()
    button.addEventListener('click',()=>{paused=!paused;refresh()})
    if(typeof IntersectionObserver==='function'){
      new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;refresh()},{threshold:0}).observe(scene)
    }else{visible=true;refresh()}
    if(typeof ResizeObserver==='function')new ResizeObserver(resize).observe(scene)
    else addEventListener('resize',resize)
    document.addEventListener('visibilitychange',refresh)
    motion.addEventListener('change',refresh)
    addEventListener('pagehide',()=>{cancelAnimationFrame(frame);previous=0})
    addEventListener('pageshow',refresh)
  }
}
