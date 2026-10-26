// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
// Three.js is MIT licensed; its notice is shipped with the bundled asset.
import {
  ACESFilmicToneMapping, CircleGeometry, CylinderGeometry, DataTexture,
  DirectionalLight, DoubleSide, ExtrudeGeometry, Group, HemisphereLight,
  LinearFilter, Mesh, MeshBasicMaterial, MeshPhysicalMaterial, MeshStandardMaterial,
  PerspectiveCamera, PlaneGeometry, PMREMGenerator, PointLight, RepeatWrapping,
  RGBAFormat, Scene, Shape, ShapeGeometry, SphereGeometry, SRGBColorSpace,
  Vector2, WebGLRenderer,
} from 'three'
import {RoomEnvironment} from 'three/addons/environments/RoomEnvironment.js'
import {RoundedBoxGeometry} from 'three/addons/geometries/RoundedBoxGeometry.js'

const turn=Math.PI*2
function roundedRect(width,height,radius){
  const x=-width/2,y=-height/2,r=Math.min(radius,width/2,height/2)
  return new Shape().moveTo(x+r,y).lineTo(x+width-r,y)
    .quadraticCurveTo(x+width,y,x+width,y+r).lineTo(x+width,y+height-r)
    .quadraticCurveTo(x+width,y+height,x+width-r,y+height).lineTo(x+r,y+height)
    .quadraticCurveTo(x,y+height,x,y+height-r).lineTo(x,y+r)
    .quadraticCurveTo(x,y,x+r,y)
}
function shell(width,depth,height,radius,bevel,materials){
  const geometry=new ExtrudeGeometry(roundedRect(width-bevel*2,depth-bevel*2,radius-bevel),{
    depth:height,steps:1,curveSegments:12,bevelEnabled:bevel>0,
    bevelThickness:bevel,bevelSize:bevel,bevelSegments:4,
  })
  geometry.rotateX(-Math.PI/2)
  return new Mesh(geometry,materials)
}
function texture(size,pixel){
  const data=new Uint8Array(size*size*4)
  for(let y=0;y<size;y++)for(let x=0;x<size;x++)data.set(pixel(x,y),4*(y*size+x))
  const map=new DataTexture(data,size,size,RGBAFormat)
  map.minFilter=map.magFilter=LinearFilter;map.needsUpdate=true
  return map
}

export function createLaptopModel(canvas){
  const context=canvas.getContext('webgl2',{alpha:true,antialias:true,powerPreference:'low-power'})
  if(!context)throw new Error('3D unavailable')
  const renderer=new WebGLRenderer({canvas,context,alpha:true,antialias:true})
  renderer.setPixelRatio(Math.max(1,Math.min(devicePixelRatio||1,1.75)))
  renderer.setClearColor(0x000000,0)
  renderer.outputColorSpace=SRGBColorSpace
  renderer.toneMapping=ACESFilmicToneMapping;renderer.toneMappingExposure=1.05
  const world=new Scene()
  const camera=new PerspectiveCamera(23,15/7,.1,30)
  camera.position.set(4,3.5,5.6);camera.lookAt(0,-.12,0);camera.zoom=1.22

  const environment=new RoomEnvironment(),pmrem=new PMREMGenerator(renderer)
  const reflection=pmrem.fromScene(environment,.05)
  world.environment=reflection.texture;world.environmentIntensity=.85;world.environmentRotation.y=.6
  environment.dispose();pmrem.dispose()
  world.add(new HemisphereLight(0xe8f0ff,0x1d291b,.55))
  const key=new DirectionalLight(0xf3f5ff,1.8);key.position.set(-3,5,4);world.add(key)
  const fill=new DirectionalLight(0xe0edff,.8);fill.position.set(5,2,-3);world.add(fill)
  const green=new PointLight(0xb0ec68,.45,10,2);green.position.set(-3,2,-3);world.add(green)

  // Fine anodized grain changes roughness, not the metal's silhouette.
  const grain=texture(64,(x,y)=>{
    const noise=(Math.imul(x+1,374761393)^Math.imul(y+1,668265263))>>>0
    const value=218+noise%24
    return [value,value,value,255]
  })
  grain.wrapS=grain.wrapT=RepeatWrapping;grain.repeat.set(18,14)
  const aluminum=new MeshPhysicalMaterial({color:0x151f2c,metalness:1,roughness:.34,roughnessMap:grain,clearcoat:.02,clearcoatRoughness:.4})
  const edge=new MeshPhysicalMaterial({color:0x354254,metalness:1,roughness:.37})
  const bottomMetal=new MeshStandardMaterial({color:0x192635,metalness:.96,roughness:.4})
  const dark=new MeshStandardMaterial({color:0x070b0d,roughness:.65,metalness:.3})
  const rubber=new MeshStandardMaterial({color:0x101311,roughness:.95})
  const socketMetal=new MeshStandardMaterial({color:0x485568,metalness:1,roughness:.3,side:DoubleSide})
  const socketBlack=new MeshStandardMaterial({color:0x040607,roughness:.7,side:DoubleSide})
  const socketTongue=new MeshStandardMaterial({color:0x354044,metalness:.6,roughness:.5,side:DoubleSide})
  const laptop=new Group();world.add(laptop)
  const base=shell(3.6,2.5,.0525,.125,.004,[bottomMetal,edge]);laptop.add(base)
  const seam=shell(3.586,2.486,.005,.12,0,dark);seam.position.y=.0565;laptop.add(seam)
  const lid=shell(3.606,2.506,.019,.13,.003,[aluminum,edge]);lid.position.y=.0645;laptop.add(lid)

  function box(width,height,depth,material,x,y,z,radius=.01){
    const mesh=new Mesh(new RoundedBoxGeometry(width,height,depth,3,radius),material)
    mesh.position.set(x,y,z);laptop.add(mesh);return mesh
  }
  // The rear hinge and the front lift recess make the closed layers readable.
  box(2.84,.024,.027,dark,0,.055,-1.246,.009)
  for(const x of [-1.44,1.44])box(.19,.02,.026,edge,x,.055,-1.248,.006)
  const recess=new Mesh(new ShapeGeometry(roundedRect(.34,.011,.005)),socketBlack)
  recess.position.set(0,.058,1.254);laptop.add(recess)
  box(.29,.003,.003,edge,0,.05,1.254,.001)

  function port(side,z,width,height,kind='usb'){
    const housing=new Group();housing.position.set(side*1.802,.027,z);housing.rotation.y=side*Math.PI/2
    const rim=new Mesh(new ShapeGeometry(roundedRect(width+.012,height+.006,.009)),socketMetal)
    const hole=new Mesh(new ShapeGeometry(roundedRect(width,height,.007)),socketBlack);hole.position.z=.001
    housing.add(rim,hole)
    if(kind==='usb'){
      const tongue=new Mesh(new PlaneGeometry(width*.66,.004),socketTongue);tongue.position.set(0,-.003,.002);housing.add(tongue)
    }
    laptop.add(housing)
  }
  // Air-style I/O: charging and two USB-C ports on the left, audio on the right.
  port(-1,-.98,.19,.017,'power');port(-1,-.62,.12,.022);port(-1,-.34,.12,.022)
  const audio=new Mesh(new CircleGeometry(.014,24),socketBlack)
  audio.rotation.y=Math.PI/2;audio.position.set(1.811,.027,-.88);laptop.add(audio)
  const charging=new Mesh(new CircleGeometry(.0035,12),new MeshBasicMaterial({color:0xb8e593}))
  charging.rotation.y=-Math.PI/2;charging.position.set(-1.813,.028,-.83);laptop.add(charging)

  for(const x of [-1.34,1.34])for(const z of [-.83,.83]){
    const foot=new Mesh(new CylinderGeometry(.07,.067,.014,24),rubber)
    foot.position.set(x,-.01,z);laptop.add(foot)
  }
  for(const x of [-1.53,0,1.53])for(const z of [-.99,.99]){
    const screw=new Mesh(new CylinderGeometry(.012,.012,.002,16),socketMetal)
    screw.position.set(x,-.005,z);laptop.add(screw)
    box(.012,.001,.002,dark,x,-.006,z,.0005)
  }

  // A restrained, dark UFO engraving on the lid echoes the floating Glee artwork.
  const engraving=new MeshStandardMaterial({color:0x070c12,metalness:.95,roughness:.35})
  const mark=new Group();mark.position.set(0,.0869,0)
  const disk=new Mesh(new CylinderGeometry(.105,.105,.0004,48),engraving);disk.scale.z=.42;mark.add(disk)
  const dome=new Mesh(new SphereGeometry(.055,32,12,0,turn,0,Math.PI/2),engraving);dome.scale.y=.02;mark.add(dome)
  laptop.add(mark)

  const shadowMap=texture(128,(x,y)=>{
    const radius=Math.hypot((x-63.5)/63.5,(y-63.5)/63.5)
    return [0,0,0,Math.round(Math.max(0,1-radius)**2*210)]
  })
  const shadow=new Mesh(new PlaneGeometry(5.6,4.4),new MeshBasicMaterial({map:shadowMap,transparent:true,depthWrite:false,opacity:.75}))
  shadow.rotation.x=-Math.PI/2;shadow.position.y=-.29;world.add(shadow)
  const target=new Vector2(),pointer=new Vector2()

  return {
    resize(width,height){
      camera.aspect=width/height;camera.updateProjectionMatrix()
      renderer.setSize(width,height,false);renderer.render(world,camera)
    },
    pointer(x,y){target.set(x,y)},
    render(seconds,delta){
      const phase=seconds*turn/28
      pointer.lerp(target,1-Math.exp(-Math.min(delta,.1)*4))
      const pitch=.05+.13*Math.sin(phase*2)+pointer.y*.035
      const yaw=-.1+.45*Math.sin(phase)+pointer.x*.055
      const roll=.065*Math.sin(phase+.5)-pointer.x*.018
      laptop.rotation.set(pitch,yaw,roll,'YXZ')
      laptop.position.y=.045+.027*Math.sin(phase*2+.4)
      shadow.scale.setScalar(1-.025*Math.sin(phase*2+.4))
      renderer.render(world,camera)
      return [pitch,yaw,roll].map(value=>value*180/Math.PI)
    },
  }
}
