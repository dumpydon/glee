// Copyright © 2026 dumpydon. SPDX-License-Identifier: AGPL-3.0-only
import release from './download/release.json'

const policy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "media-src 'self'",
  "frame-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "frame-ancestors 'self'",
  "form-action 'none'",
].join('; ')

export default {
  async fetch(request, env) {
    const {pathname} = new URL(request.url)
    if (pathname === '/get' || pathname === '/get/') {
      return Response.redirect(release.dmg, 302)
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', {status:405, headers:{Allow:'GET, HEAD'}})
    }
    const response = await env.ASSETS.fetch(request)
    const headers = new Headers(response.headers)
    headers.set('Content-Security-Policy', policy)
    headers.set('X-Content-Type-Options', 'nosniff')
    headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
    headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()')
    headers.set('X-Frame-Options', 'SAMEORIGIN')
    if (headers.get('Content-Type')?.includes('text/html')) headers.set('Cache-Control', 'public, max-age=0, must-revalidate')
    return new Response(response.body, {status:response.status, statusText:response.statusText, headers})
  }
}
