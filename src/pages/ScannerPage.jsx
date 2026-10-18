import { useEffect, useRef, useState } from 'react'
import { Camera, CheckCircle2, RefreshCw, Search, SwitchCamera, XCircle } from 'lucide-react'
import { Html5Qrcode } from 'html5-qrcode'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { formatWitaTime } from '../utils/normalize'

function tokenFromScan(value) {
  const raw = String(value || '').trim()
  if (!raw) return ''
  try {
    const url = new URL(raw)
    const parts = url.pathname.split('/').filter(Boolean)
    if (parts[0] === 'ticket' && parts[1]) return parts[1]
  } catch {}
  return raw.replace(/^SVPQR:/i, '')
}

function getPreferredCamera(cameras = []) {
  if (!cameras.length) return null
  const rear = cameras.find((c) => /back|rear|environment/i.test(c.label || ''))
  return rear || cameras[0]
}

export default function ScannerPage() {
  const { secret } = useOutletContext()
  const scannerRef = useRef(null)
  const [active, setActive] = useState(false)
  const [busy, setBusy] = useState(false)
  const [manual, setManual] = useState('')
  const [participant, setParticipant] = useState(null)
  const [token, setToken] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [cameras, setCameras] = useState([])
  const [cameraId, setCameraId] = useState('')

  async function stopScanner() {
    const scanner = scannerRef.current
    if (scanner) {
      try {
        if (scanner.isScanning) await scanner.stop()
      } catch {}
      try { scanner.clear() } catch {}
      scannerRef.current = null
    }
    setActive(false)
  }

  async function inspect(scanned) {
    if (busy) return
    const parsed = tokenFromScan(scanned)
    if (!parsed) return
    setBusy(true)
    setError('')
    setMessage('')
    await stopScanner()
    const { data, error: rpcError } = await supabase.rpc('lookup_attendance_qr', {
      p_secret: secret,
      p_token: parsed,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message || 'QR gagal diperiksa.')
    if (!data) return setError('QR tidak valid atau peserta tidak ditemukan.')
    setToken(parsed)
    setParticipant(data)
  }

  async function loadCameras() {
    try {
      const list = await Html5Qrcode.getCameras()
      setCameras(list || [])
      const preferred = getPreferredCamera(list || [])
      if (preferred && !cameraId) setCameraId(preferred.id)
      return list || []
    } catch (e) {
      setError(`Daftar kamera tidak dapat dibaca: ${e?.message || e}`)
      return []
    }
  }

  async function startScanner(requestedCameraId = cameraId) {
    setError('')
    setMessage('')
    setParticipant(null)
    setToken('')

    await stopScanner()

    let available = cameras
    if (!available.length) available = await loadCameras()
    if (!available.length) {
      setError('Tidak ada kamera yang terdeteksi. Cek permission browser dan perangkat kamera.')
      return
    }

    const chosen = available.find((c) => c.id === requestedCameraId) || getPreferredCamera(available)
    if (!chosen) return
    setCameraId(chosen.id)

    const scanner = new Html5Qrcode('qr-reader', { verbose: false })
    scannerRef.current = scanner

    try {
      await scanner.start(
        chosen.id,
        {
          fps: 10,
          qrbox: (viewfinderWidth, viewfinderHeight) => {
            const edge = Math.floor(Math.min(viewfinderWidth, viewfinderHeight) * 0.72)
            return { width: Math.max(180, edge), height: Math.max(180, edge) }
          },
          aspectRatio: 1.333333,
          disableFlip: false,
        },
        (text) => inspect(text),
        () => {}
      )

      setActive(true)

      // html5-qrcode creates the video element asynchronously.
      // Force browser-friendly video attributes/styles for iOS, Android and desktop browsers.
      requestAnimationFrame(() => {
        const video = document.querySelector('#qr-reader video')
        if (video) {
          video.setAttribute('playsinline', 'true')
          video.setAttribute('autoplay', 'true')
          video.muted = true
          video.style.display = 'block'
          video.style.width = '100%'
          video.style.height = '100%'
          video.style.objectFit = 'cover'
          video.style.opacity = '1'
          video.play?.().catch(() => {})
        }
      })
    } catch (e) {
      console.error('Scanner start error:', e)
      setError(`Kamera gagal menampilkan preview: ${e?.message || e}. Coba pilih kamera lain atau refresh halaman.`)
      try { scanner.clear() } catch {}
      scannerRef.current = null
      setActive(false)
    }
  }

  async function changeCamera(e) {
    const nextId = e.target.value
    setCameraId(nextId)
    if (active) await startScanner(nextId)
  }

  async function confirm() {
    if (!token) return
    setBusy(true)
    setError('')
    const { data, error: rpcError } = await supabase.rpc('confirm_attendance', {
      p_secret: secret,
      p_token: token,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message || 'Check-in gagal.')
    setParticipant((p) => ({ ...p, attendance_status: 'ATTENDED', checked_in_at: data.checked_in_at }))
    setMessage(data.already_attended ? 'Peserta ini sudah pernah check-in.' : 'Kehadiran berhasil dikonfirmasi.')
  }

  function reset() {
    setParticipant(null)
    setToken('')
    setManual('')
    setMessage('')
    setError('')
  }

  useEffect(() => {
    loadCameras()
    return () => { stopScanner() }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return <section>
    <div className="page-header">
      <div>
        <div className="eyebrow">ATTENDANCE CONTROL</div>
        <h1>Scan QR</h1>
        <p className="muted">Scan QR peserta dari tablet/HP untuk konfirmasi kehadiran.</p>
      </div>
    </div>

    <div className="scanner-grid">
      <div className="glass scanner-panel">
        {cameras.length > 1 && (
          <label className="camera-select-wrap">
            <span><SwitchCamera size={15}/> Kamera</span>
            <select value={cameraId} onChange={changeCamera}>
              {cameras.map((camera, idx) => (
                <option key={camera.id} value={camera.id}>{camera.label || `Kamera ${idx + 1}`}</option>
              ))}
            </select>
          </label>
        )}

        <div id="qr-reader" className={`qr-reader ${active ? 'is-active' : ''}`} />

        {!active && !participant && (
          <button className="btn primary full" onClick={() => startScanner()}>
            <Camera size={18}/> Buka Kamera & Scan
          </button>
        )}
        {active && (
          <button className="btn ghost full" onClick={stopScanner}>
            <XCircle size={18}/> Tutup Kamera
          </button>
        )}

        <div className="scanner-divider"><span>atau</span></div>
        <div className="manual-scan">
          <input value={manual} onChange={e => setManual(e.target.value)} placeholder="Paste token / URL QR"/>
          <button className="btn ghost" onClick={() => inspect(manual)}><Search size={17}/> Cek</button>
        </div>
      </div>

      <div className="glass scan-result-panel">
        {!participant ? (
          <div className="scanner-empty">
            <Camera size={42}/>
            <strong>Menunggu QR</strong>
            <span>Data peserta akan muncul di sini setelah QR berhasil dibaca.</span>
          </div>
        ) : <>
          <div className={`scan-status ${participant.attendance_status === 'ATTENDED' ? 'attended' : 'ready'}`}>
            {participant.attendance_status === 'ATTENDED' ? <CheckCircle2/> : <Camera/>}
            <span>{participant.attendance_status === 'ATTENDED' ? 'SUDAH CHECK-IN' : 'QR VALID'}</span>
          </div>
          <h2>{participant.full_name}</h2>
          <div className="scan-meta">
            <div><span>Nama Mitra</span><strong>{participant.partner_name}</strong></div>
            <div><span>Jabatan</span><strong>{participant.position}</strong></div>
            <div><span>Kode</span><strong>{participant.registration_code}</strong></div>
            <div><span>Check-in</span><strong>{participant.checked_in_at ? formatWitaTime(participant.checked_in_at) : '-'}</strong></div>
          </div>
          {message && <div className="success-box">{message}</div>}
          {error && <div className="error-box">{error}</div>}
          {participant.attendance_status !== 'ATTENDED' && (
            <button className="btn primary full" disabled={busy} onClick={confirm}>
              <CheckCircle2 size={18}/>{busy ? 'Memproses...' : 'Konfirmasi Kehadiran'}
            </button>
          )}
          <button className="btn ghost full" onClick={reset}><RefreshCw size={17}/> Scan Peserta Berikutnya</button>
        </>}
        {!participant && error && <div className="error-box">{error}</div>}
      </div>
    </div>
  </section>
}
