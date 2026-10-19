import { ExternalLink,Loader2 } from 'lucide-react'
import { useState } from 'react'
const secret=()=>sessionStorage.getItem('sena_admin_secret')||''
export default function AdminFileLink({file}){
  const [busy,setBusy]=useState(false)
  if(!file?.path)return <span>-</span>
  async function openFile(){
    setBusy(true)
    try{
      const res=await fetch('/api/admin-file-url',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({secret:secret(),path:file.path})})
      const data=await res.json().catch(()=>({}))
      if(!res.ok||!data.url)throw new Error(data.error||'File tidak dapat dibuka.')
      window.open(data.url,'_blank','noopener,noreferrer')
    }catch(e){alert(e.message)}finally{setBusy(false)}
  }
  return <button className="file-open-btn" type="button" onClick={openFile} disabled={busy} title={file.name||'Buka file'}>{busy?<Loader2 size={14} className="spin"/>:<ExternalLink size={14}/>}<span>{file.name||'Buka File'}</span></button>
}
