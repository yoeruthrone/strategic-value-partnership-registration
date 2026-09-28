import { useMemo, useState } from 'react'
import { ArrowLeft, Check, Plus, Trash2, Users } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { normalizePhone, normalizeText } from '../utils/normalize'
import DuplicateModal from '../components/DuplicateModal'
import LogoMark from '../components/LogoMark'

const emptyMember = () => ({ full_name: '', position: '' })

export default function RegisterPage() {
  const eventName = import.meta.env.VITE_EVENT_NAME || 'Strategic Value Partnership'
  const [form, setForm] = useState({ full_name: '', phone: '', partner_name: '', position: '', attendance_type: 'SELF' })
  const [members, setMembers] = useState([])
  const [status, setStatus] = useState('idle')
  const [error, setError] = useState('')
  const [duplicate, setDuplicate] = useState(null)
  const [success, setSuccess] = useState(null)

  const totalPeople = useMemo(() => 1 + members.length, [members])

  function updateField(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }))
    setError('')
  }

  function changeAttendance(value) {
    updateField('attendance_type', value)
    if (value === 'SELF') setMembers([])
    if (value === 'TEAM' && members.length === 0) setMembers([emptyMember()])
  }

  function addMember() {
    if (members.length >= 10) return
    setMembers((prev) => [...prev, emptyMember()])
  }

  function updateMember(index, key, value) {
    setMembers((prev) => prev.map((m, i) => i === index ? { ...m, [key]: value } : m))
  }

  function removeMember(index) {
    setMembers((prev) => prev.filter((_, i) => i !== index))
  }

  function normalizedPayload() {
    return {
      full_name: normalizeText(form.full_name),
      phone: normalizePhone(form.phone),
      partner_name: normalizeText(form.partner_name),
      position: normalizeText(form.position),
      attendance_type: form.attendance_type,
      members: members.map((m) => ({ full_name: normalizeText(m.full_name), position: normalizeText(m.position) })),
    }
  }

  function validate(payload) {
    if (!payload.full_name || !payload.phone || !payload.partner_name || !payload.position) return 'Semua field utama wajib diisi.'
    if (payload.phone.length < 8) return 'Nomor telepon belum valid.'
    if (payload.attendance_type === 'TEAM') {
      if (payload.members.length < 1 || payload.members.length > 10) return 'Jumlah anggota tim harus 1 sampai 10 orang.'
      if (payload.members.some((m) => !m.full_name || !m.position)) return 'Nama dan jabatan seluruh anggota tim wajib diisi.'
    }
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
      p_members: payload.members,
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
    const { data, error: rpcError } = await supabase.rpc('submit_registration', {
      p_primary: {
        full_name: payload.full_name,
        phone: payload.phone,
        partner_name: payload.partner_name,
        position: payload.position,
        attendance_type: payload.attendance_type,
      },
      p_members: payload.members,
    })
    if (rpcError) {
      setStatus('idle')
      return setError(rpcError.message || 'Registrasi gagal. Silakan coba lagi.')
    }
    setSuccess({ name: payload.full_name, partner: payload.partner_name, total: data?.participant_count || totalPeople })
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
          <div className="success-meta">
            <div><span>Asal Mitra</span><strong>{success.partner}</strong></div>
            <div><span>Total Peserta</span><strong>{success.total} orang</strong></div>
          </div>
          <button
            className="btn ghost success-back"
            type="button"
            onClick={() => {
              setSuccess(null)
              setStatus('idle')
              setForm({ full_name: '', phone: '', partner_name: '', position: '', attendance_type: 'SELF' })
              setMembers([])
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
              <span>Asal Mitra *</span>
              <input value={form.partner_name} onChange={(e) => updateField('partner_name', e.target.value)} placeholder="Nama perusahaan / mitra" />
            </label>
            <label>
              <span>Jabatan *</span>
              <input value={form.position} onChange={(e) => updateField('position', e.target.value)} placeholder="Jabatan" />
            </label>
          </div>

          <div className="section-divider" />
          <div className="field-title">Kehadiran *</div>
          <div className="attendance-grid">
            <button type="button" className={`choice-card ${form.attendance_type === 'SELF' ? 'active' : ''}`} onClick={() => changeAttendance('SELF')}>
              <span className="choice-dot" />
              <div><strong>Hadir Sendiri</strong><small>Registrasi hanya untuk Anda.</small></div>
            </button>
            <button type="button" className={`choice-card ${form.attendance_type === 'TEAM' ? 'active' : ''}`} onClick={() => changeAttendance('TEAM')}>
              <span className="choice-dot" />
              <div><strong>Bersama Tim</strong><small>Maksimal 10 anggota tambahan.</small></div>
            </button>
          </div>

          {form.attendance_type === 'TEAM' && (
            <div className="team-section">
              <div className="team-heading">
                <div><Users size={20} /><strong>Anggota Tim</strong></div>
                <span>{members.length} / 10 anggota</span>
              </div>
              {members.map((member, index) => (
                <div className="member-card" key={index}>
                  <div className="member-title">Anggota {index + 1}<button type="button" onClick={() => removeMember(index)} aria-label="Hapus anggota"><Trash2 size={17} /></button></div>
                  <div className="form-grid compact">
                    <label><span>Nama Lengkap *</span><input value={member.full_name} onChange={(e) => updateMember(index, 'full_name', e.target.value)} placeholder="Nama anggota" /></label>
                    <label><span>Jabatan *</span><input value={member.position} onChange={(e) => updateMember(index, 'position', e.target.value)} placeholder="Jabatan anggota" /></label>
                  </div>
                </div>
              ))}
              <button className="btn add-member" type="button" onClick={addMember} disabled={members.length >= 10}><Plus size={18} /> Tambah Anggota</button>
            </div>
          )}

          {error && <div className="error-box">{error}</div>}
          <button className="btn primary submit-btn" type="submit" disabled={status === 'checking' || status === 'saving'}>
            {status === 'checking' ? 'Memeriksa Data...' : status === 'saving' ? 'Menyimpan...' : `Daftar Sekarang • ${totalPeople} Peserta`}
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
