import { useMemo,useState } from 'react'
import { ArrowDownAZ,ArrowUpAZ,ChevronLeft,ChevronRight,RefreshCw,Search } from 'lucide-react'
import { dateWita,timeWita,fieldValue } from '../utils/format'

const getValue=(r,key)=>{
  if(key==='date')return new Date(r.created_at||0).getTime()
  if(key==='time')return new Date(r.created_at||0).getTime()
  if(key==='status')return r.attendance_status||''
  if(key==='checkin')return r.checked_in_at?new Date(r.checked_in_at).getTime():0
  if(key.startsWith('custom:'))return fieldValue(r.custom_data?.[key.slice(7)]).toLowerCase()
  return String(r[key]??'').toLowerCase()
}
function SortButton({active,direction,onClick}){return <button className={`sort-btn ${active?'active':''}`} onClick={onClick} title="Urutkan kolom">{active&&direction==='asc'?<ArrowUpAZ size={14}/>:<ArrowDownAZ size={14}/>}</button>}
export default function RegistrationTable({rows=[],fields=[],onRefresh,showToolbar=true,title='Data Pendaftaran'}){
 const [q,setQ]=useState('');const [sort,setSort]=useState({key:'date',direction:'desc'});const [size,setSize]=useState(20);const [page,setPage]=useState(1)
 const columns=[{key:'date',label:'Tanggal'},{key:'time',label:'Waktu'},{key:'full_name',label:'Nama'},{key:'phone',label:'No. Telepon'},{key:'email',label:'Email'},...fields.map(f=>({key:`custom:${f.field_key}`,label:f.label,field:f})),{key:'status',label:'Status'},{key:'checkin',label:'Check-in'}]
 const filtered=useMemo(()=>rows.filter(r=>!q||JSON.stringify(r).toLowerCase().includes(q.toLowerCase())),[rows,q])
 const sorted=useMemo(()=>[...filtered].sort((a,b)=>{const av=getValue(a,sort.key),bv=getValue(b,sort.key);if(av===bv)return 0;const n=av>bv?1:-1;return sort.direction==='asc'?n:-n}),[filtered,sort])
 const pages=Math.max(1,Math.ceil(sorted.length/size));const safePage=Math.min(page,pages);const visible=sorted.slice((safePage-1)*size,safePage*size)
 function toggle(key){setPage(1);setSort(s=>s.key===key?{key,direction:s.direction==='asc'?'desc':'asc'}:{key,direction:key==='date'||key==='time'?'desc':'asc'})}
 return <section className="registration-section"><div className="table-section-head"><div><h3>{title}</h3><p>{filtered.length} data ditemukan</p></div>{onRefresh&&<button className="btn secondary" onClick={onRefresh}><RefreshCw size={16}/> Refresh</button>}</div>
 {showToolbar&&<div className="table-toolbar"><div className="toolbar search-toolbar"><Search size={17}/><input placeholder="Cari seluruh data pendaftaran..." value={q} onChange={e=>{setQ(e.target.value);setPage(1)}}/></div><label className="page-size">Tampilkan<select value={size} onChange={e=>{setSize(Number(e.target.value));setPage(1)}}>{[20,50,100,200].map(n=><option key={n} value={n}>{n}</option>)}</select></label></div>}
 <div className="table-scroll"><table><thead><tr>{columns.map(c=><th key={c.key}><div className="th-sort"><span>{c.label}</span><SortButton active={sort.key===c.key} direction={sort.direction} onClick={()=>toggle(c.key)}/></div></th>)}</tr></thead><tbody>{visible.map(r=><tr key={r.id}><td>{dateWita(r.created_at)}</td><td>{timeWita(r.created_at)}</td><td>{r.full_name}</td><td>{r.phone}</td><td>{r.email}</td>{fields.map(f=><td key={f.id}>{fieldValue(r.custom_data?.[f.field_key])||'-'}</td>)}<td><span className={`pill ${r.attendance_status==='ATTENDED'?'success':''}`}>{r.attendance_status==='ATTENDED'?'HADIR':'BELUM'}</span></td><td>{r.checked_in_at?`${dateWita(r.checked_in_at)} ${timeWita(r.checked_in_at)}`:'-'}</td></tr>)}{visible.length===0&&<tr><td colSpan={columns.length} className="table-empty">Belum ada data pendaftaran.</td></tr>}</tbody></table></div>
 <div className="pagination"><span>Halaman {safePage} dari {pages}</span><div><button className="icon-btn" disabled={safePage<=1} onClick={()=>setPage(p=>Math.max(1,p-1))}><ChevronLeft size={17}/></button><button className="icon-btn" disabled={safePage>=pages} onClick={()=>setPage(p=>Math.min(pages,p+1))}><ChevronRight size={17}/></button></div></div></section>
}
