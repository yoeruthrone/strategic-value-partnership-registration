import { useState } from 'react'
import { ArrowLeft, Search } from 'lucide-react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { normalizePhone } from '../utils/normalize'
import TicketCard from '../components/TicketCard'
import LogoMark from '../components/LogoMark'

export default function TicketRecoveryPage() {
  const eventName = import.meta.env.VITE_EVENT_NAME || 'Strategic Value Partnership'
  const [phone, setPhone] = useState('')
  const [code, setCode] = useState('')
  const [ticket, setTicket] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function submit(e) {
    e.preventDefault()
    setError('')
    setTicket(null)
    if (!normalizePhone(phone) || !code.trim()) return setError('No. Telepon dan Kode Registrasi wajib diisi.')
    setLoading(true)
    const { data, error: rpcError } = await supabase.rpc('recover_ticket', {
      p_phone: normalizePhone(phone),
      p_registration_code: code.trim().toUpperCase(),
    })
    setLoading(false)
    if (rpcError) return setError(rpcError.message || 'Gagal mengakses tiket.')
    if (!data) return setError('Tiket tidak ditemukan. Periksa kembali No. Telepon dan Kode Registrasi.')
    setTicket(data)
  }

  return <main className="public-shell recovery-shell">
    <div className="ambient-grid" />
    <section className="registration-wrap recovery-wrap">
      <header className="public-header">
        <LogoMark />
        <div className="eyebrow">AKSES TIKET SAYA</div>
        <h1>{eventName}</h1>
        <p className="muted">QR hilang? Masukkan No. Telepon dan Kode Registrasi untuk menampilkan tiket yang sama.</p>
      </header>

      {!ticket ? <form className="glass registration-card" onSubmit={submit}>
        <div className="form-grid single-column">
          <label><span>No. Telepon *</span><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="08xxxxxxxxxx" inputMode="numeric" /></label>
          <label><span>Kode Registrasi *</span><input value={code} onChange={e=>setCode(e.target.value)} placeholder="SVP-XXXXXXXX" autoCapitalize="characters" /></label>
        </div>
        {error && <div className="error-box">{error}</div>}
        <button className="btn primary submit-btn" disabled={loading}><Search size={17}/>{loading ? 'Mencari Tiket...' : 'Tampilkan Tiket'}</button>
        <Link className="btn ghost recovery-back" to="/register"><ArrowLeft size={17}/> Kembali ke Registrasi</Link>
      </form> : <>
        <TicketCard ticket={ticket}/>
        <button className="btn ghost recovery-reset" onClick={()=>{setTicket(null);setError('')}}><ArrowLeft size={17}/> Cari Tiket Lain</button>
      </>}
    </section>
  </main>
}
