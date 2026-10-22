import { useEffect,useMemo,useRef,useState } from 'react';
import { Link,useParams } from 'react-router-dom';
import { FileText,Image as ImageIcon,Trash2,Upload,UserPlus,Users } from 'lucide-react';
import { supabase } from '../lib/supabase';
import ThemeToggle from '../components/ThemeToggle';
import TicketCard from '../components/TicketCard';
import EventBrandHero from '../components/EventBrandHero';
import PublicFooter from '../components/PublicFooter';
import { normalizePhone } from '../utils/format';
import { bytesLabel,prepareRegistrationImage } from '../utils/image';
import { eventThemeStorageKey,eventThemeStyle } from '../utils/theme';

const MAX_FILE=1024*1024;
const MAX_GUESTS=10;
const allowedImage=['image/jpeg','image/png','image/webp'];
const uid=()=>globalThis.crypto?.randomUUID?.()||`${Date.now()}-${Math.random().toString(36).slice(2)}`;
const extFor=(file)=>file.type==='application/pdf'?'pdf':file.type==='image/webp'?'webp':file.type==='image/png'?'png':'jpg';
const fileSignature=(f)=>f?`${f.name}:${f.size}:${f.lastModified}`:'';
const newGuest=()=>({id:uid(),full_name:'',phone:'',email:''});

export default function RegisterPage(){
 const {slug}=useParams();
 const [cfg,setCfg]=useState(null);
 const [form,setForm]=useState({full_name:'',phone:'',email:'',custom_data:{}});
 const [guests,setGuests]=useState([]);
 const [files,setFiles]=useState({});
 const [uploaded,setUploaded]=useState({});
 const [ticket,setTicket]=useState(null);
 const [error,setError]=useState('');
 const [busy,setBusy]=useState(false);
 const uploadSession=useRef(uid());
 useEffect(()=>{supabase.rpc('v3_public_event_config',{p_slug:slug}).then(({data})=>setCfg(data))},[slug]);
 const custom=cfg?.fields||[];
 const visibleFields=useMemo(()=>custom.filter(f=>!f.show_if_field_key||form.custom_data?.[f.show_if_field_key]===(f.show_if_value||'YA')),[custom,form.custom_data]);

 function setCustom(key,val){
  setForm(prev=>{const next={...prev.custom_data,[key]:val};for(const f of custom){if(f.show_if_field_key===key&&val!==(f.show_if_value||'YA'))delete next[f.field_key]}return {...prev,custom_data:next}});
  const hidden=custom.filter(f=>f.show_if_field_key===key&&val!==(f.show_if_value||'YA')).map(f=>f.field_key);
  if(hidden.length){
   setFiles(prev=>{const n={...prev};hidden.forEach(k=>delete n[k]);return n});
   setUploaded(prev=>{const n={...prev};hidden.forEach(k=>delete n[k]);return n});
  }
 }
 function chooseFile(field,file){
  if(!file){setFiles(p=>{const n={...p};delete n[field.field_key];return n});return}
  const rule=field.allowed_file_type||'image_pdf';const isPdf=file.type==='application/pdf';const isImage=allowedImage.includes(file.type);
  if(!isPdf&&!isImage)return alert('Format file harus JPG, PNG, WEBP atau PDF.');
  if(rule==='image'&&!isImage)return alert('Field ini hanya menerima gambar.');
  if(rule==='pdf'&&!isPdf)return alert('Field ini hanya menerima PDF.');
  if(isPdf&&file.size>MAX_FILE)return alert('PDF maksimal 1 MB.');
  if(isImage&&file.size>8*MAX_FILE)return alert('Gambar maksimal 8 MB sebelum kompresi.');
  setFiles(p=>({...p,[field.field_key]:file}));
  setUploaded(p=>{const n={...p};delete n[field.field_key];return n});
 }
 async function uploadFile(field,file){
  const sig=fileSignature(file);if(uploaded[field.field_key]?.signature===sig)return uploaded[field.field_key].meta;
  let prepared=file;if(file.type.startsWith('image/'))prepared=await prepareRegistrationImage(file,{maxBytes:MAX_FILE});
  if(prepared.size>MAX_FILE)throw new Error(`${field.label}: file maksimal 1 MB.`);
  const path=`${cfg.event.id}/${uploadSession.current}/${field.field_key}/${uid()}.${extFor(prepared)}`;
  const {error:uploadError}=await supabase.storage.from('registration-files').upload(path,prepared,{contentType:prepared.type,upsert:false});
  if(uploadError)throw new Error(`${field.label}: ${uploadError.message}`);
  const meta={path,name:prepared.name,size:prepared.size,type:prepared.type};
  setUploaded(p=>({...p,[field.field_key]:{signature:sig,meta}}));return meta;
 }
 function addGuest(){if(guests.length>=MAX_GUESTS)return;setGuests(g=>[...g,newGuest()])}
 function updateGuest(id,key,value){setGuests(g=>g.map(x=>x.id===id?{...x,[key]:value}:x))}
 function removeGuest(id){setGuests(g=>g.filter(x=>x.id!==id))}
 function resetForm(){setTicket(null);setForm({full_name:'',phone:'',email:'',custom_data:{}});setGuests([]);setFiles({});setUploaded({});uploadSession.current=uid()}

 async function submit(e){
  e.preventDefault();setBusy(true);setError('');
  try{
   const activeKeys=new Set(visibleFields.map(f=>f.field_key));
   const custom_data=Object.fromEntries(Object.entries(form.custom_data).filter(([k])=>activeKeys.has(k)));
   for(const field of visibleFields.filter(f=>f.field_type==='file')){
    const file=files[field.field_key];
    if(field.required&&!file&&!uploaded[field.field_key])throw new Error(`${field.label} wajib diupload.`);
    if(file)custom_data[field.field_key]=await uploadFile(field,file);else if(uploaded[field.field_key])custom_data[field.field_key]=uploaded[field.field_key].meta;
   }
   const payload={...form,custom_data,phone:normalizePhone(form.phone),email:form.email.trim().toLowerCase(),guests:guests.map(({id,...g})=>({...g,phone:normalizePhone(g.phone),email:g.email.trim().toLowerCase()}))};
   const {data,error}=await supabase.rpc('v3_public_register',{p_slug:slug,p_payload:payload});
   if(error)throw error;setTicket(data);
  }catch(err){setError(err.message||'Registrasi gagal.')}finally{setBusy(false)}
 }

 if(!cfg)return <div className="public-page"><div className="public-card">Memuat...</div></div>;
 const pageStyle=eventThemeStyle(cfg.event,cfg.event.background_data_url?{backgroundImage:`linear-gradient(var(--public-bg-overlay),var(--public-bg-overlay)),url(${cfg.event.background_data_url})`}:{});
 const themeProps={storageKey:eventThemeStorageKey(cfg.event),defaultTheme:cfg.event.default_theme||'dark'};
 if(!cfg.event.registration_open)return <div className="public-page branded-public" style={pageStyle}><div className="public-top registration-public-top"><ThemeToggle {...themeProps}/></div><div className="public-card event-public-card"><EventBrandHero event={cfg.event}/><div className="public-card-body"><div className="alert">Registrasi sudah ditutup.</div></div></div><PublicFooter/></div>;
 if(ticket)return <div className="public-page branded-public" style={pageStyle}><div className="public-top registration-public-top"><ThemeToggle {...themeProps}/></div><div className="public-card success-card event-public-card"><EventBrandHero event={cfg.event} eyebrow="REGISTRASI BERHASIL"/><div className="public-card-body"><h2>Selamat Datang, {ticket.full_name}</h2><p>{ticket.guest_count>0?`Satu QR ini berlaku untuk kamu dan ${ticket.guest_count} peserta tambahan.`:'Simpan QR ini untuk konfirmasi kehadiran.'}</p><TicketCard ticket={ticket} event={cfg.event}/>{ticket.guest_count>0&&<GuestSummary guests={ticket.guests}/>}<button className="btn secondary wide" onClick={resetForm}>Kembali ke Form</button></div></div><PublicFooter/></div>;
 return <div className="public-page branded-public" style={pageStyle}><div className="public-top registration-public-top"><ThemeToggle {...themeProps}/></div><form className="public-card event-public-card" onSubmit={submit}><EventBrandHero event={cfg.event}/><div className="public-card-body"><div className="form-stack public-form-stack"><FieldBlock label="Nama Lengkap *" helper={cfg.event.name_description}><input value={form.full_name} onChange={e=>setForm({...form,full_name:e.target.value})} required/></FieldBlock><FieldBlock label="No. Telepon *" helper={cfg.event.phone_description}><input inputMode="tel" value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})} required/></FieldBlock><FieldBlock label="Email *" helper={cfg.event.email_description}><input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})} required/></FieldBlock>{visibleFields.map(f=><DynamicField key={f.id} field={f} value={f.field_type==='file'?files[f.field_key]:form.custom_data[f.field_key]} onChange={v=>f.field_type==='file'?chooseFile(f,v):setCustom(f.field_key,v)}/>)}</div><GuestSection guests={guests} addGuest={addGuest} updateGuest={updateGuest} removeGuest={removeGuest}/>{error&&<div className="alert error">{error}</div>}<button className="btn primary wide" disabled={busy}>{busy?'Memproses...':'Daftar Sekarang'}</button><div className="recover-link">Sudah mendaftar tapi lupa QR saya? <Link to={`/e/${slug}/recover`}>Cek QR Disini</Link></div></div></form><PublicFooter/></div>
}

function GuestSection({guests,addGuest,updateGuest,removeGuest}){return <section className="guest-section"><div className="guest-section-head"><div><div className="eyebrow">PESERTA TAMBAHAN</div><h3>Bawa orang lain?</h3><p>Kamu bisa menambahkan maksimal 10 orang. Mereka cukup mengisi Nama, No. Telepon, dan Email, serta akan menggunakan QR leader yang sama.</p></div><span className="guest-count"><Users size={16}/>{guests.length}/10</span></div>{guests.length>0&&<div className="guest-list">{guests.map((g,i)=><div className="guest-card" key={g.id}><div className="guest-card-head"><strong>Peserta Tambahan {i+1}</strong><button type="button" className="icon-btn danger" onClick={()=>removeGuest(g.id)} title="Hapus peserta"><Trash2 size={16}/></button></div><div className="guest-fields"><label>Nama Lengkap *<input value={g.full_name} onChange={e=>updateGuest(g.id,'full_name',e.target.value)} required/></label><label>No. Telepon *<input inputMode="tel" value={g.phone} onChange={e=>updateGuest(g.id,'phone',e.target.value)} required/></label><label>Email *<input type="email" value={g.email} onChange={e=>updateGuest(g.id,'email',e.target.value)} required/></label></div></div>)}</div>}<button type="button" className="btn secondary guest-add-btn" onClick={addGuest} disabled={guests.length>=MAX_GUESTS}><UserPlus size={17}/>{guests.length?'Tambah Orang Lagi':'Tambah Peserta'}</button></section>}
function GuestSummary({guests=[]}){return <div className="ticket-guests"><div className="ticket-guests-head"><Users size={18}/><strong>Peserta Tambahan ({guests.length})</strong></div>{guests.map((g,i)=><div className="ticket-guest-row" key={g.id||`${g.email}-${i}`}><span>{i+1}. {g.full_name}</span><small>{g.email}</small></div>)}</div>}
function FieldBlock({label,helper,reference,children,className=''}){return <div className={`public-field-block ${className}`}><div className="public-field-copy"><label className="field-block-label">{label}</label>{helper&&<span className="field-helper">{helper}</span>}</div>{reference&&<div className="field-reference"><img src={reference} alt="Contoh / referensi"/></div>}<div className="field-control">{children}</div></div>}
function DynamicField({field,value,onChange}){const req=field.required;const label=`${field.label}${req?' *':''}`;const ref=field.reference_image_data_url;if(field.field_type==='file')return <FieldBlock label={label} helper={field.description} reference={ref} className="file-field-block"><FileUploadControl field={field} value={value} onChange={onChange}/></FieldBlock>;if(['yes_no','conditional_choice'].includes(field.field_type))return <FieldBlock label={label} helper={field.description} reference={ref}><div className="choice-row">{(field.options||['YA','TIDAK']).map(o=><label className="choice" key={o}><input type="radio" name={field.field_key} checked={value===o} onChange={()=>onChange(o)} required={req}/>{o}</label>)}</div></FieldBlock>;if(field.field_type==='textarea')return <FieldBlock label={label} helper={field.description} reference={ref}><textarea value={value||''} onChange={e=>onChange(e.target.value)} required={req}/></FieldBlock>;if(field.field_type==='dropdown')return <FieldBlock label={label} helper={field.description} reference={ref}><select value={value||''} onChange={e=>onChange(e.target.value)} required={req}><option value="">Pilih...</option>{(field.options||[]).map(o=><option key={o}>{o}</option>)}</select></FieldBlock>;if(field.field_type==='radio')return <FieldBlock label={label} helper={field.description} reference={ref}><div className="choice-row">{(field.options||[]).map(o=><label className="choice" key={o}><input type="radio" name={field.field_key} checked={value===o} onChange={()=>onChange(o)} required={req}/>{o}</label>)}</div></FieldBlock>;if(field.field_type==='checkbox')return <FieldBlock label={label} helper={field.description} reference={ref}><div className="choice-row">{(field.options||[]).map(o=><label className="choice" key={o}><input type="checkbox" checked={(value||[]).includes(o)} onChange={e=>onChange(e.target.checked?[...(value||[]),o]:(value||[]).filter(x=>x!==o))}/>{o}</label>)}</div></FieldBlock>;if(field.field_type==='date')return <FieldBlock label={label} helper={field.description} reference={ref}><input type="date" value={value||''} onChange={e=>onChange(e.target.value)} required={req}/></FieldBlock>;return <FieldBlock label={label} helper={field.description} reference={ref}><input type={field.field_type==='number'?'number':'text'} value={value||''} onChange={e=>onChange(e.target.value)} required={req}/></FieldBlock>}
function FileUploadControl({field,value,onChange}){const accept=field.allowed_file_type==='image'?'image/jpeg,image/png,image/webp':field.allowed_file_type==='pdf'?'application/pdf':'image/jpeg,image/png,image/webp,application/pdf';const rule=field.allowed_file_type==='image'?'JPG, PNG, WEBP':field.allowed_file_type==='pdf'?'PDF':'JPG, PNG, WEBP atau PDF';return <div className="upload-control">{value?<div className="selected-file"><div className="selected-file-icon">{value.type==='application/pdf'?<FileText size={22}/>:<ImageIcon size={22}/>}</div><div><strong>{value.name}</strong><span>{bytesLabel(value.size)}{value.type.startsWith('image/')&&value.size>MAX_FILE?' • akan dikompres':''}</span></div><button type="button" className="icon-btn danger" onClick={()=>onChange(null)}><Trash2 size={16}/></button></div>:<label className="upload-drop"><Upload size={22}/><strong>Pilih File</strong><span>{rule} • Maks. 1 MB setelah optimasi</span><input type="file" accept={accept} onChange={e=>onChange(e.target.files?.[0]||null)}/></label>}</div>}
