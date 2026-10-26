import { useEffect,useMemo,useState } from 'react'
import { useParams } from 'react-router-dom'
import { Archive,Download,FileText } from 'lucide-react'
import { supabase } from '../lib/supabase'
import EventNav from '../components/EventNav'
import RegistrationTable from '../components/RegistrationTable'
import { exportExcel,exportPdf } from '../utils/exporters'
const secret=()=>sessionStorage.getItem('sena_admin_secret')||''
export default function ParticipantsPage(){
 const {eventId}=useParams()
 const [d,setD]=useState({event:null,fields:[],archived_fields:[],participants:[]})
 const [showArchived,setShowArchived]=useState(false)
 async function load(){const {data,error}=await supabase.rpc('v3_admin_participants',{p_secret:secret(),p_event_id:eventId});if(error)alert(error.message);else if(data)setD(data)}
 useEffect(()=>{load()},[eventId])
 const displayFields=useMemo(()=>showArchived?[...(d.fields||[]),...(d.archived_fields||[])]:d.fields||[],[d.fields,d.archived_fields,showArchived])
 return <div className="page"><header className="page-head"><div><div className="eyebrow">PARTICIPANTS</div><h1>{d.event?.name||'Peserta'}</h1></div><div className="button-row">{(d.archived_fields||[]).length>0&&<button className={`btn secondary ${showArchived?'active':''}`} onClick={()=>setShowArchived(v=>!v)}><Archive size={16}/>{showArchived?'Sembunyikan Arsip':'Tampilkan Field Arsip'}</button>}<button className="btn secondary" onClick={()=>exportExcel(d.participants,displayFields,d.event?.name,{name:d.event?.name_label||'Nama',phone:d.event?.phone_label||'No. Telepon',email:d.event?.email_label||'Email'})}><Download size={17}/> Excel</button><button className="btn secondary" onClick={()=>exportPdf(d.participants,displayFields,d.event?.name,{name:d.event?.name_label||'Nama',phone:d.event?.phone_label||'No. Telepon',email:d.event?.email_label||'Email'})}><FileText size={17}/> PDF</button></div></header><EventNav/>{showArchived&&(d.archived_fields||[]).length>0&&<div className="archive-data-note"><Archive size={16}/><span>Field arsip ditampilkan untuk membaca data historis. Field ini tidak muncul pada registrasi baru.</span></div>}<RegistrationTable rows={d.participants} fields={displayFields} onRefresh={load} title="Data Pendaftaran" coreLabels={{name:d.event?.name_label||'Nama',phone:d.event?.phone_label||'No. Telepon',email:d.event?.email_label||'Email'}}/></div>
}
