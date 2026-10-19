import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Eye, EyeOff } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { startAdminSession } from '../lib/adminSession'
import Brand from '../components/Brand'
import ThemeToggle from '../components/ThemeToggle'

export default function AdminLoginPage() {
  const [secret, setSecret] = useState('')
  const [showSecret, setShowSecret] = useState(false)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const nav = useNavigate()

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError('')
    const { data, error } = await supabase.rpc('v3_admin_verify', { p_secret: secret })
    setBusy(false)
    if (error || !data) {
      setError('Secret admin tidak valid.')
      return
    }
    startAdminSession(secret)
    nav('/admin/events')
  }

  return (
    <div className="auth-page">
      <div className="top-theme"><ThemeToggle /></div>
      <form className="auth-card" onSubmit={submit}>
        <Brand />
        <div>
          <div className="eyebrow">INTERNAL CONTROL</div>
          <h1>Admin</h1>
          <p>Kelola seluruh event, registrasi, QR, attendance dan viewer eksternal.</p>
        </div>
        <label>
          Admin Secret
          <div className="secret-input-wrap">
            <input
              type={showSecret ? 'text' : 'password'}
              value={secret}
              onChange={e => setSecret(e.target.value)}
              required
              autoFocus
              autoComplete="current-password"
            />
            <button
              type="button"
              className="secret-eye-btn"
              onClick={() => setShowSecret(v => !v)}
              aria-label={showSecret ? 'Sembunyikan secret' : 'Tampilkan secret'}
              title={showSecret ? 'Sembunyikan secret' : 'Tampilkan secret'}
            >
              {showSecret ? <EyeOff size={18} /> : <Eye size={18} />}
            </button>
          </div>
        </label>
        {error && <div className="alert error">{error}</div>}
        <button className="btn primary wide" disabled={busy}>{busy ? 'Memeriksa...' : 'Masuk'}</button>
      </form>
    </div>
  )
}
