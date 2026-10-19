import { useEffect } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { CalendarDays, LogOut } from 'lucide-react'
import Brand from './Brand'
import ThemeToggle from './ThemeToggle'
import { clearAdminSession, getAdminSession } from '../lib/adminSession'

export default function AdminShell() {
  const nav = useNavigate()

  useEffect(() => {
    const logoutExpired = () => {
      const session = getAdminSession()
      if (!session) {
        clearAdminSession()
        nav('/admin', { replace: true })
        return null
      }
      return session
    }

    const session = logoutExpired()
    if (!session) return undefined

    const timeoutId = window.setTimeout(() => {
      clearAdminSession()
      nav('/admin', { replace: true })
    }, Math.max(0, session.expiresAt - Date.now()))

    const recheck = () => logoutExpired()
    window.addEventListener('focus', recheck)
    document.addEventListener('visibilitychange', recheck)

    return () => {
      window.clearTimeout(timeoutId)
      window.removeEventListener('focus', recheck)
      document.removeEventListener('visibilitychange', recheck)
    }
  }, [nav])

  const logout = () => {
    clearAdminSession()
    nav('/admin', { replace: true })
  }

  return (
    <div className="admin-shell">
      <aside className="sidebar">
        <Brand compact />
        <nav><NavLink to="/admin/events"><CalendarDays size={18} />Events</NavLink></nav>
        <div className="sidebar-bottom">
          <ThemeToggle />
          <button className="icon-btn" onClick={logout} title="Logout" aria-label="Logout"><LogOut size={18} /></button>
        </div>
      </aside>
      <main className="admin-main"><Outlet /></main>
    </div>
  )
}
