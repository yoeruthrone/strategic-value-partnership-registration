import { useState } from 'react'
import { ArrowLeft, Check } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { normalizePhone, normalizeText } from '../utils/normalize'
import DuplicateModal from '../components/DuplicateModal'
import LogoMark from '../components/LogoMark'

export default function RegisterPage() {
  const eventName = import.meta.env.VITE_EVENT_NAME || 'Strategic Value Partnership'
  const [form, setForm] = useState({ full_name: '', phone: '', partner_name: '', position: '' })
  const [status, setStatus] = useState('idle')
  const [error, setError] = useState('')
  const [duplicate, setDuplicate] = useState(null)
  const [success, setSuccess] = useState(null)

  function updateField(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }))
    setError('')
  }

  function normalizedPayload() {
    return {
      full_name: normalizeText(form.full_name),
      phone: normalizePhone(form.phone),
      partner_name: normalizeText(form.partner_name),
      position: normalizeText(form.position),
    }
  }

  function validate(payload) {
    if (!payload.full_name || !payload.phone || !payload.partner_name || !payload.position) return 'Semua field wajib diisi.'
    if (payload.phone.length < 8) return 'Nomor telepon belum valid.'
    return ''
  }

  async function handleSubmit(e) {
    e?.preventDefault()
    const payload = normalizedPayload()
    const validationError = validate(payload)
    if (validationError) return setError(validationError)

    setStatus('checking')
    setError('')
    const { data, error: rpcError } = await supabase.rpc('check_registration_duplicates', {
      p_partner: payload.partner_name,
      p_primary_name: payload.full_name,
      p_phone: payload.phone,
      p_members: [],
    })
    if (rpcError) {
      setStatus('idle')
      return setError(rpcError.message || 'Gagal memeriksa data.')
    }
    if (data?.has_duplicate) {
      setDuplicate({ ...data, payload })
      setStatus('idle')
      return
    }
    await save(payload)
  }

  async function save(payload) {
    setStatus('saving')
    setDuplicate(null)
    const { error: rpcError } = await supabase.rpc('submit_registration', {
      p_primary: {
        full_name: payload.full_name,
        phone: payload.phone,
        partner_name: payload.partner_name,
        position: payload.position,
        attendance_type: 'SELF',
      },
      p_members: [],
    })
    if (rpcError) {
      setStatus('idle')
      return setError(rpcError.message || 'Registrasi gagal. Silakan coba lagi.')
    }
    setSuccess({ name: payload.full_name, partner: payload.partner_name })
    setStatus('success')
  }

  if (success) {
    return (
      <main className="public-shell">
        <div className="ambient-grid" />
        <section className="success-card glass strong-glow">
          <div className="success-icon"><Check size={42} /></div>
          <div className="eyebrow">REGISTRASI BERHASIL</div>
          <h1>SELAMAT DATANG,<br /><span className="gradient-text">{success.name}</span></h1>
          <p className="muted">Terima kasih telah melakukan registrasi. Kami menantikan kehadiran Anda di {eventName}.</p>
          <div className="success-meta single-meta">
            <div><span>Nama Mitra</span><strong>{success.partner}</strong></div>
          </div>
          <button
            className="btn ghost success-back"
            type="button"
            onClick={() => {
              setSuccess(null)
              setStatus('idle')
              setForm({ full_name: '', phone: '', partner_name: '', position: '' })
              setError('')
            }}
          >
            <ArrowLeft size={17} /> Kembali ke Form
          </button>
        </section>
      </main>
    )
  }

  return (
    <main className="public-shell">
      <div className="ambient-grid" />
      <section className="registration-wrap">
        <header className="public-header">
          <LogoMark />
          <div className="eyebrow">EVENT REGISTRATION</div>
          <h1>{eventName}</h1>
          <p className="muted">Isi data di bawah ini untuk melakukan registrasi.</p>
        </header>

        <form className="glass registration-card" onSubmit={handleSubmit}>
          <div className="form-grid">
            <label>
              <span>Nama Lengkap *</span>
              <input value={form.full_name} onChange={(e) => updateField('full_name', e.target.value)} placeholder="Nama lengkap" autoComplete="name" />
            </label>
            <label>
              <span>No. Telepon *</span>
              <input value={form.phone} onChange={(e) => updateField('phone', e.target.value)} placeholder="08xxxxxxxxxx" inputMode="numeric" autoComplete="tel" />
            </label>
            <label>
              <span>Nama Mitra *</span>
              <input value={form.partner_name} onChange={(e) => updateField('partner_name', e.target.value)} placeholder="Nama perusahaan / mitra" />
            </label>
            <label>
              <span>Jabatan *</span>
              <input value={form.position} onChange={(e) => updateField('position', e.target.value)} placeholder="Jabatan" />
            </label>
          </div>

          {error && <div className="error-box">{error}</div>}
          <button className="btn primary submit-btn" type="submit" disabled={status === 'checking' || status === 'saving'}>
            {status === 'checking' ? 'Memeriksa Data...' : status === 'saving' ? 'Menyimpan...' : 'Daftar Sekarang'}
          </button>
        </form>
      </section>
      <DuplicateModal
        open={Boolean(duplicate)}
        result={duplicate}
        onCancel={() => setDuplicate(null)}
        onContinue={() => save(duplicate.payload)}
      />
    </main>
  )
}
