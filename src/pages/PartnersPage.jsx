import { useEffect, useMemo, useState } from 'react'
import { Search, Users } from 'lucide-react'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import DataTable from '../components/DataTable'
import Loading from '../components/Loading'

export default function PartnersPage() {
  const { secret } = useOutletContext()
  const [partners, setPartners] = useState([])
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState({ key: 'participant_count', dir: 'desc' })
  const [selected, setSelected] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { (async () => { const { data } = await supabase.rpc('partners_report', { p_secret: secret }); setPartners(data || []); setLoading(false) })() }, [secret])

  const rows = useMemo(() => partners.filter((r) => !query || r.partner_name.includes(query.trim().toUpperCase())).sort((a,b) => {
    const av=a[sort.key], bv=b[sort.key]; const result = typeof av === 'number' ? av-bv : av.localeCompare(bv,'id'); return sort.dir==='asc'?result:-result
  }), [partners, query, sort])
  const columns = [
    { key: 'partner_name', label: 'Asal Mitra' },
    { key: 'participant_count', label: 'Jumlah Peserta', render: (r) => <button className="count-link" onClick={() => setSelected(r)}><Users size={15}/>{r.participant_count}</button> },
  ]
  function onSort(key){setSort((s)=>({key,dir:s.key===key&&s.dir==='asc'?'desc':'asc'}))}

  return <section>
    <div className="page-header"><div><div className="eyebrow">PARTNER OVERVIEW</div><h1>Total Mitra</h1><p className="muted">{partners.length} mitra unik terdaftar.</p></div></div>
    <div className="toolbar"><div className="search-box"><Search size={18}/><input value={query} onChange={(e)=>setQuery(e.target.value.toUpperCase())} placeholder="Cari mitra..." /></div></div>
    {loading ? <Loading/> : <DataTable columns={columns} rows={rows} sort={sort} onSort={onSort}/>} 
    {selected && <div className="modal-backdrop" onClick={()=>setSelected(null)}><div className="modal glass partner-modal" onClick={(e)=>e.stopPropagation()}><div className="eyebrow">DETAIL MITRA</div><h3>{selected.partner_name}</h3><p className="muted">{selected.participant_count} peserta</p><div className="partner-people">{(selected.participants||[]).map((p)=><div key={p.id}><div><strong>{p.full_name}</strong><span>{p.position}</span></div><span className="type-badge">{p.participant_type==='PRIMARY'?'UTAMA':'ANGGOTA'}</span></div>)}</div><button className="btn ghost full" onClick={()=>setSelected(null)}>Tutup</button></div></div>}
  </section>
}
