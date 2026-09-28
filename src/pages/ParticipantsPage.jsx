import { useEffect, useMemo, useRef, useState } from 'react'
import { ChevronDown, Download, FileSpreadsheet, FileText, Search } from 'lucide-react'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { formatWitaTime } from '../utils/normalize'
import { exportParticipantsExcel, exportParticipantsPdf } from '../utils/exporters'
import DataTable from '../components/DataTable'
import PaginationBar from '../components/PaginationBar'
import Loading from '../components/Loading'

export default function ParticipantsPage() {
  const { secret } = useOutletContext()
  const [data, setData] = useState([])
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState({ key: 'created_at', dir: 'desc' })
  const [pageSize, setPageSize] = useState(20)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [exportOpen, setExportOpen] = useState(false)
  const exportRef = useRef(null)
  const eventName = import.meta.env.VITE_EVENT_NAME || 'Strategic Value Partnership'
  const spreadsheetUrl = import.meta.env.VITE_SPREADSHEET_URL || ''

  useEffect(() => { (async () => { const { data: rows } = await supabase.rpc('participants_report', { p_secret: secret }); setData(rows || []); setLoading(false) })() }, [secret])


  useEffect(() => {
    function onPointerDown(e) {
      if (exportRef.current && !exportRef.current.contains(e.target)) setExportOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [])

  function openSpreadsheet() {
    setExportOpen(false)
    if (spreadsheetUrl) window.open(spreadsheetUrl, '_blank', 'noopener,noreferrer')
    else window.alert('Google Spreadsheet belum dikonfigurasi. Isi VITE_SPREADSHEET_URL jika fitur ini akan digunakan.')
  }

  const filtered = useMemo(() => {
    const q = query.trim().toUpperCase()
    return data.filter((r) => !q || Object.values(r).some((v) => (v || '').toString().toUpperCase().includes(q))).sort((a, b) => {
      const av = a[sort.key] || '', bv = b[sort.key] || ''
      const result = sort.key === 'created_at' ? new Date(av) - new Date(bv) : av.toString().localeCompare(bv.toString(), 'id')
      return sort.dir === 'asc' ? result : -result
    })
  }, [data, query, sort])

  const totalPages = Math.ceil(filtered.length / pageSize)
  const rows = filtered.slice((page - 1) * pageSize, page * pageSize)
  const columns = [
    { key: 'created_at', label: 'Waktu', render: (r) => formatWitaTime(r.created_at) },
    { key: 'full_name', label: 'Nama' },
    { key: 'phone', label: 'No. Telp', render: (r) => r.phone || '-' },
    { key: 'partner_name', label: 'Nama Mitra' },
    { key: 'position', label: 'Jabatan' },
  ]
  function onSort(key) { setSort((s) => ({ key, dir: s.key === key && s.dir === 'asc' ? 'desc' : 'asc' })); setPage(1) }

  return <section>
    <div className="page-header">
      <div><div className="eyebrow">PARTICIPANT DATABASE</div><h1>Total Peserta</h1><p className="muted">{data.length} peserta terdaftar.</p></div>
      <div className="export-wrap" ref={exportRef}>
        <button className="btn primary export-trigger" type="button" onClick={() => setExportOpen((v) => !v)}>
          <Download size={17}/> Export <ChevronDown size={16} className={exportOpen ? 'rotate-180' : ''}/>
        </button>
        {exportOpen && (
          <div className="export-menu glass">
            <button type="button" onClick={() => { setExportOpen(false); exportParticipantsExcel(data) }}><FileSpreadsheet size={17}/><span><strong>Excel</strong><small>Download file .xlsx</small></span></button>
            <button type="button" onClick={() => { setExportOpen(false); exportParticipantsPdf(data, eventName) }}><FileText size={17}/><span><strong>PDF</strong><small>Download laporan PDF</small></span></button>
            <button type="button" onClick={openSpreadsheet}><FileSpreadsheet size={17}/><span><strong>Spreadsheet</strong><small>{spreadsheetUrl ? 'Buka Google Spreadsheet' : 'Belum dikonfigurasi'}</small></span></button>
          </div>
        )}
      </div>
    </div>
    <div className="toolbar"><div className="search-box"><Search size={18}/><input value={query} onChange={(e) => {setQuery(e.target.value);setPage(1)}} placeholder="Cari seluruh data peserta..." /></div></div>
    {loading ? <Loading/> : <><DataTable columns={columns} rows={rows} sort={sort} onSort={onSort}/><PaginationBar pageSize={pageSize} setPageSize={setPageSize} page={page} totalPages={totalPages} setPage={setPage}/></>}
  </section>
}
