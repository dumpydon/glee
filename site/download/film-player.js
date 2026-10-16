// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
// The round control follows actual media events, including pause, errors, and replay.
export function setupFilmPlayers(root=document){
  const players=Array.from(root.querySelectorAll('[data-film-player]'))
  players.forEach((player,index)=>{
    const video=player.querySelector('video'),toggle=player.querySelector('.film-toggle')
    const tools=player.querySelector('.film-tools'),sound=player.querySelector('.film-sound')
    const fullscreen=player.querySelector('.film-fullscreen'),error=player.querySelector('.film-error')
    video.id='glee-film-'+index
    toggle.setAttribute('aria-controls',video.id)
    function sync(){
      const state=video.ended?'replay':video.paused?'play':'pause'
      const action=state[0].toUpperCase()+state.slice(1)
      toggle.setAttribute('aria-label',action+' Glee launch film');toggle.title=action
      player.dataset.playback=state
      toggle.querySelectorAll('[data-film-icon]').forEach(icon=>icon.toggleAttribute('hidden',icon.dataset.filmIcon!==state))
      const audioAction=video.muted?'Unmute':'Mute'
      sound.setAttribute('aria-label',audioAction+' Glee launch film');sound.title=audioAction
      sound.querySelectorAll('[data-sound-icon]').forEach(icon=>icon.toggleAttribute('hidden',icon.dataset.soundIcon!==(video.muted?'off':'on')))
    }
    async function togglePlayback(){
      if(!video.paused&&!video.ended){video.pause();return}
      error.hidden=true
      players.forEach(other=>{if(other!==player)other.querySelector('video').pause()})
      if(video.ended)video.currentTime=0
      try{await video.play()}catch(reason){if(reason.name!=='AbortError')error.hidden=false;sync()}
    }
    async function toggleFullscreen(){
      try{
        if(document.fullscreenElement===player)await document.exitFullscreen()
        else if(player.requestFullscreen)await player.requestFullscreen()
        else if(video.webkitEnterFullscreen)video.webkitEnterFullscreen()
      }catch{/* Keep the inline player usable if full screen is unavailable. */}
    }
    toggle.addEventListener('click',togglePlayback)
    video.addEventListener('click',()=>{if(player.classList.contains('film-enhanced'))togglePlayback()})
    sound.addEventListener('click',()=>{video.muted=!video.muted})
    fullscreen.addEventListener('click',toggleFullscreen)
    document.addEventListener('fullscreenchange',()=>{
      const active=document.fullscreenElement===player
      fullscreen.setAttribute('aria-label',(active?'Exit full screen for':'Show')+' Glee launch film'+(active?'':' full screen'))
      fullscreen.title=active?'Exit full screen':'Full screen'
    })
    for(const event of ['play','pause','ended','volumechange','loadedmetadata','seeked'])video.addEventListener(event,sync)
    video.addEventListener('error',()=>{
      error.hidden=false;video.controls=true;toggle.hidden=true;tools.hidden=true;player.classList.remove('film-enhanced')
    })
    // Native controls are the no-JavaScript and media-error fallback.
    video.controls=false;toggle.hidden=false;tools.hidden=false;player.classList.add('film-enhanced');sync()
  })
}
