const SECRET_KEY = 'sena_admin_secret'
const EXPIRES_KEY = 'sena_admin_expires_at'
export const ADMIN_SESSION_MS = 60 * 60 * 1000

export function startAdminSession(secret) {
  const expiresAt = Date.now() + ADMIN_SESSION_MS
  sessionStorage.setItem(SECRET_KEY, secret)
  sessionStorage.setItem(EXPIRES_KEY, String(expiresAt))
  return expiresAt
}

export function clearAdminSession() {
  sessionStorage.removeItem(SECRET_KEY)
  sessionStorage.removeItem(EXPIRES_KEY)
}

export function getAdminSession() {
  const secret = sessionStorage.getItem(SECRET_KEY)
  const expiresAt = Number(sessionStorage.getItem(EXPIRES_KEY) || 0)
  if (!secret || !expiresAt || Date.now() >= expiresAt) {
    clearAdminSession()
    return null
  }
  return { secret, expiresAt }
}

export function getAdminSecret() {
  return getAdminSession()?.secret || ''
}
