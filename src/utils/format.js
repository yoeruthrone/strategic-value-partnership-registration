export const wita=(iso,withDate=false)=>{if(!iso)return '-';return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Makassar',...(withDate?{day:'2-digit',month:'short',year:'numeric'}:{}),hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(iso))}
export const dateWita=(iso)=>{if(!iso)return '-';return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Makassar',day:'2-digit',month:'2-digit',year:'numeric'}).format(new Date(iso))}
export const timeWita=(iso)=>{if(!iso)return '-';return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Makassar',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(iso))}
export const formatEventDate=(value)=>{if(!value)return 'Tanggal belum ditentukan';const d=new Date(`${value}T12:00:00+08:00`);return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Makassar',day:'numeric',month:'long',year:'numeric'}).format(d).toUpperCase()}
export const normalizePhone=(v='')=>v.replace(/\D/g,'')
export const slugify=(v='')=>v.toLowerCase().trim().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')
export const fieldValue=(v)=>{if(Array.isArray(v))return v.join(', ');if(v&&typeof v==='object')return v.name||v.file_name||'File';return String(v??'')}
