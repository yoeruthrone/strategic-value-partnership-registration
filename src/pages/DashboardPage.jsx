import { useCallback, useEffect, useMemo, useState } from 'react'
import { Building2, CheckCircle2, Clock3, RefreshCw, Search, Users } from 'lucide-react'
import { useNavigate, useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { formatWitaTime } from '../utils/normalize'
import StatCard from '../components/StatCard'
import DataTable from '../components/DataTable'
import PaginationBar from '../components/PaginationBar'
import Loading from '../components/Loading'

export default function DashboardPage() {
  const { secret } = useOutletContext()
  const navigate = useNavigate()
  const [snapshot, setSnapshot] = useState({ participants: [], total_participants: 0, total_partners: 0, total_attended: 0, total_not_attended: 0 })
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState({ key: 'created_at', dir: 'desc' })
  const [pageSize, setPageSize] = useState(20)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true)
    const { data, error: rpcError } = await supabase.rpc('dashboard_snapshot', { p_secret: secret })
    if (rpcError) setError(rpcError.message)
    else { setSnapshot(data || { participants: [], total_participants: 0, total_partners: 0, total_attended: 0, total_not_attended: 0 }); setError('') }
    setLoading(false)
  }, [secret])

  useEffect(() => {
    load()
    const channel = supabase.channel('registration-signal')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'dashboard_signal' }, () => load(true))
      .subscribe()
    const fallback = setInterval(() => load(true), 15000)
    return () => { clearInterval(fallback); supabase.removeChannel(channel) }
  }, [load])

  const filtered = useMemo(() => {
    const q = query.trim().toUpperCase()
    const data = (snapshot.participants || []).filter((r) => !q || [r.full_name, r.phone, r.partner_name, r.position].some((v) => (v || '').toString().toUpperCase().includes(q)))
    return data.sort((a, b) => {
      const av = a[sort.key] || ''
      const bv = b[sort.key] || ''
      const result = sort.key === 'created_at' ? new Date(av) - new Date(bv) : av.toString().localeCompare(bv.toString(), 'id')
      return sort.dir === 'asc' ? result : -result
    })
  }, [snapshot.participants, query, sort])

  const totalPages = Math.ceil(filtered.length / pageSize)
  const rows = filtered.slice((page - 1) * pageSize, page * pageSize)

  function onSort(key) { setSort((s) => ({ key, dir: s.key === key && s.dir === 'asc' ? 'desc' : 'asc' })); setPage(1) }

  const columns = [
    { key: 'created_at', label: 'Waktu', render: (r) => <span className="time-pill">{formatWitaTime(r.created_at)}</span> },
    { key: 'full_name', label: 'Nama Lengkap' },
    { key: 'phone', label: 'No. Telp', render: (r) => r.phone || '-' },
    { key: 'partner_name', label: 'Nama Mitra' },
    { key: 'position', label: 'Jabatan' },
    { key: 'attendance_status', label: 'Kehadiran', render: (r) => <span className={`attendance-pill table-status ${r.attendance_status === 'ATTENDED' ? 'attended' : ''}`}>{r.attendance_status === 'ATTENDED' ? 'HADIR' : 'BELUM HADIR'}</span> },
  ]

  return (
    <section>
      <div className="page-header"><div><div className="eyebrow">LIVE REGISTRATION</div><h1>Dashboard</h1><p className="muted">Monitoring registrasi peserta secara langsung.</p></div><button className="btn ghost" onClick={() => load()}><RefreshCw size={17} />Refresh</button></div>
      <div className="live-badge"><span /> Live • Auto Refresh</div>
      <div className="stats-grid">
        <StatCard label="Total Peserta" value={snapshot.total_participants} icon={<Users />} onClick={() => navigate(`/internal/${secret}/participants`)} />
        <StatCard label="Total Mitra" value={snapshot.total_partners} icon={<Building2 />} onClick={() => navigate(`/internal/${secret}/partners`)} />
        <StatCard label="Sudah Hadir" value={snapshot.total_attended || 0} icon={<CheckCircle2 />} onClick={() => navigate(`/internal/${secret}/scanner`)} />
        <StatCard label="Belum Hadir" value={snapshot.total_not_attended || 0} icon={<Clock3 />} onClick={() => navigate(`/internal/${secret}/participants`)} />
      </div>
      <div className="toolbar"><div className="search-box"><Search size={18} /><input value={query} onChange={(e) => { setQuery(e.target.value); setPage(1) }} placeholder="Cari nama, nomor telepon, mitra, jabatan..." /></div></div>
      {error && <div className="error-box">{error}</div>}
      {loading ? <Loading /> : <><DataTable columns={columns} rows={rows} sort={sort} onSort={onSort} /><PaginationBar pageSize={pageSize} setPageSize={setPageSize} page={page} totalPages={totalPages} setPage={setPage} /></>}
    </section>
  )
}
