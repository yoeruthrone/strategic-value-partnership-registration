import { useEffect,useMemo,useState } from 'react'
import { useParams } from 'react-router-dom'
import { Archive,FileUp,GitBranch,GripVertical,ImagePlus,Loader2,Plus,RotateCcw } from 'lucide-react'
import { supabase } from '../lib/supabase'
import EventNav from '../components/EventNav'
import { slugify } from '../utils/format'
import { imageFileToDataUrl } from '../utils/image'

const secret=()=>sessionStorage.getItem('sena_admin_secret')||''
const types=['text','number','date','dropdown','radio','checkbox','textarea','conditional_choice','file']
const typeLabels={text:'Text',number:'Number',date:'Date / Calendar',dropdown:'Dropdown',radio:'Radio',checkbox:'Checkbox',textarea:'Textarea',yes_no:'Ya / Tidak',conditional_choice:'Conditional Choice',file:'File Upload'}
const fileTypeLabels={image:'Image only',pdf:'PDF only',image_pdf:'Image + PDF'}
const emptyDraft=()=>({label:'',field_key:'',field_type:'text',required:false,options:'',choice_a:'',choice_b:'',description:'',allowed_file_type:'image_pdf',reference_image_data_url:null})
const isTrigger=f=>['yes_no','conditional_choice'].includes(f.field_type)
const logicValue=f=>f.show_if_field_key?`${f.show_if_field_key}:::${f.show_if_value||'YA'}`:''

export default function FormBuilderPage(){
 const {eventId}=useParams()
 const [event,setEvent]=useState(null)
 const [fields,setFields]=useState([])
 const [archived,setArchived]=useState([])
 const [draft,setDraft]=useState(emptyDraft())
 const [draggedId,setDraggedId]=useState(null)
 const [ordering,setOrdering]=useState(false)
 const [imageBusy,setImageBusy]=useState('')

 async function load(){
  const {data,error}=await supabase.rpc('v3_admin_form_config',{p_secret:secret(),p_event_id:eventId})
  if(error)return alert(error.message)
  if(data){setEvent(data.event);setFields(data.fields||[]);setArchived(data.archived_fields||[])}
 }
 useEffect(()=>{load()},[eventId])
 const triggers=useMemo(()=>fields.filter(isTrigger),[fields])

 async function upsert(f,shouldReload=true){
  const payload={...f,description:f.description||'',options:Array.isArray(f.options)?f.options:[],sort_order:f.sort_order||10,show_if_field_key:f.show_if_field_key||null,show_if_value:f.show_if_value||null,allowed_file_type:f.allowed_file_type||'image_pdf',reference_image_data_url:f.reference_image_data_url||null}
  const {error}=await supabase.rpc('v3_admin_upsert_field',{p_secret:secret(),p_event_id:eventId,p_field:payload})
  if(error){alert(error.message);return false}
  if(shouldReload)await load()
  return true
 }
 async function add(){
  if(!draft.label)return
  let options=[]
  if(draft.field_type==='conditional_choice')options=[draft.choice_a.trim(),draft.choice_b.trim()]
  else if(['dropdown','radio','checkbox'].includes(draft.field_type))options=draft.options.split(',').map(x=>x.trim()).filter(Boolean)
  if(draft.field_type==='conditional_choice'&&options.some(x=>!x))return alert('Conditional Choice wajib memiliki 2 opsi.')
  const f={...draft,field_key:draft.field_key||slugify(draft.label).replace(/-/g,'_'),options,sort_order:fields.length+10,show_if_field_key:null,show_if_value:null}
  const {error}=await supabase.rpc('v3_admin_upsert_field',{p_secret:secret(),p_event_id:eventId,p_field:f})
  if(error)alert(error.message);else{setDraft(emptyDraft());load()}
 }
 async function setLogic(field,value){
  if(!value)return upsert({...field,show_if_field_key:null,show_if_value:null})
  const [key,...rest]=value.split(':::')
  await upsert({...field,show_if_field_key:key,show_if_value:rest.join(':::')})
 }
 async function saveCoreSetting(key,value){
  const patch={[key]:value}
  const {error}=await supabase.rpc('v3_admin_event_update',{p_secret:secret(),p_event_id:eventId,p_patch:patch})
  if(error)alert(error.message);else setEvent(prev=>({...prev,...patch}))
 }
 async function archiveField(id){
  if(!confirm('Arsipkan field ini? Field akan hilang dari form baru, tetapi data peserta lama tetap tersimpan dan bisa ditampilkan kembali.'))return
  const {error}=await supabase.rpc('v3_admin_delete_field',{p_secret:secret(),p_event_id:eventId,p_field_id:id})
  if(error)alert(error.message);else load()
 }
 async function restoreField(id){
  const {error}=await supabase.rpc('v3_admin_restore_field',{p_secret:secret(),p_event_id:eventId,p_field_id:id})
  if(error)alert(error.message);else load()
 }
 async function persistOrder(next){
  setOrdering(true)
  try{for(let i=0;i<next.length;i++){const ok=await upsert({...next[i],sort_order:(i+1)*10},false);if(!ok)throw new Error('order')}await load()}
  catch{await load()}finally{setOrdering(false);setDraggedId(null)}
 }
 function dropOn(targetId){
  if(!draggedId||draggedId===targetId||ordering){setDraggedId(null);return}
  const from=fields.findIndex(f=>f.id===draggedId),to=fields.findIndex(f=>f.id===targetId)
  if(from<0||to<0)return
  const next=[...fields];const [moved]=next.splice(from,1);next.splice(to,0,moved);setFields(next);persistOrder(next)
 }
 async function referenceImage(file,target){
  if(!file)return
  setImageBusy(target)
  try{
   const data=await imageFileToDataUrl(file,{maxWidth:1200,maxHeight:700,quality:.76,maxInputMB:8})
   if(target==='draft')setDraft(d=>({...d,reference_image_data_url:data}))
   else{const f=fields.find(x=>x.id===target);if(f)await upsert({...f,reference_image_data_url:data})}
  }catch(e){alert(e.message)}finally{setImageBusy('')}
 }

 return <div className="page">
  <header className="page-head"><div><div className="eyebrow">FORM BUILDER</div><h1>{event?.name||'Form Builder'}</h1></div></header>
  <EventNav/>
  <div className="builder-grid">
   <section className="panel">
    <div className="builder-title-row"><h3>Core Fields</h3>{ordering&&<span className="ordering-status"><Loader2 size={14}/> Menyimpan urutan...</span>}</div>
    {[
      {defaultLabel:'NAMA LENGKAP',labelKey:'name_label',label:event?.name_label||'Nama Lengkap',descriptionKey:'name_description',description:event?.name_description||''},
      {defaultLabel:'NO. TELEPON',labelKey:'phone_label',label:event?.phone_label||'No. Telepon',descriptionKey:'phone_description',description:event?.phone_description||''},
      {defaultLabel:'EMAIL',labelKey:'email_label',label:event?.email_label||'Email',descriptionKey:'email_description',description:event?.email_description||''}
    ].map(x=><div className="field-row locked core-field-row" key={x.labelKey}><GripVertical size={16}/><div className="field-meta"><strong>{x.defaultLabel}</strong><span>REQUIRED • CORE • INTERNAL KEY TETAP</span><label className="core-label-editor">Label tampil<input value={x.label} placeholder={x.defaultLabel} onChange={e=>setEvent(prev=>({...prev,[x.labelKey]:e.target.value}))} onBlur={e=>saveCoreSetting(x.labelKey,e.target.value)}/></label><textarea className="field-description-input" rows="2" value={x.description} placeholder="Deskripsi / helper text (opsional)" onChange={e=>setEvent(prev=>({...prev,[x.descriptionKey]:e.target.value}))} onBlur={e=>saveCoreSetting(x.descriptionKey,e.target.value)}/></div></div>)}

    <h3 className="mt">Custom Fields</h3>
    {fields.map(f=><div className={`field-row field-row-builder draggable-field ${draggedId===f.id?'dragging':''}`} key={f.id} draggable={!ordering} onDragStart={e=>{setDraggedId(f.id);e.dataTransfer.effectAllowed='move';e.dataTransfer.setData('text/plain',f.id)}} onDragOver={e=>{e.preventDefault();e.dataTransfer.dropEffect='move'}} onDrop={e=>{e.preventDefault();dropOn(f.id)}} onDragEnd={()=>setDraggedId(null)}>
      <span className="drag-handle" title="Drag untuk mengubah urutan"><GripVertical size={18}/></span>
      <div className="field-meta">
       <label className="custom-label-editor">Label tampil<input defaultValue={f.label} placeholder="Nama field" onBlur={async e=>{const next=e.target.value.trim();if(!next){e.target.value=f.label;return alert('Label field tidak boleh kosong.')}if(next!==f.label)await upsert({...f,label:next})}}/></label>
       <span>{typeLabels[f.field_type]||f.field_type}{f.required?' • REQUIRED':''}{f.show_if_field_key?` • CONDITIONAL: ${f.show_if_value||'YA'}`:''}{f.field_type==='file'?` • ${fileTypeLabels[f.allowed_file_type||'image_pdf']} • MAX 1 MB`:''}</span>
       <span className="field-key-lock">KEY: {f.field_key} • INTERNAL KEY TETAP</span>
       {isTrigger(f)&&<div className="conditional-options-preview"><GitBranch size={14}/><span>{(f.options||[]).join(' / ')}</span></div>}
       <textarea className="field-description-input" rows="2" defaultValue={f.description||''} placeholder="Deskripsi / helper text (opsional)" onBlur={e=>upsert({...f,description:e.target.value})}/>
       {f.field_type==='file'&&<label className="inline-setting">Allowed File<select value={f.allowed_file_type||'image_pdf'} onChange={e=>upsert({...f,allowed_file_type:e.target.value})}><option value="image">Image only</option><option value="pdf">PDF only</option><option value="image_pdf">Image + PDF</option></select></label>}
       <ReferenceImageEditor value={f.reference_image_data_url} busy={imageBusy===f.id} onPick={file=>referenceImage(file,f.id)} onRemove={()=>upsert({...f,reference_image_data_url:null})}/>
       {!isTrigger(f)&&triggers.length>0&&<label className="logic-inline"><GitBranch size={14}/><select value={logicValue(f)} onChange={e=>setLogic(f,e.target.value)} disabled={ordering}><option value="">Selalu tampil</option>{triggers.filter(t=>t.id!==f.id).flatMap(t=>(t.options||[]).map(option=><option key={`${t.id}-${option}`} value={`${t.field_key}:::${option}`}>Tampil jika “{t.label}” = {option}</option>))}</select></label>}
      </div>
      <button className="icon-btn danger" onClick={()=>archiveField(f.id)} disabled={ordering} title="Arsipkan field"><Archive size={16}/></button>
     </div>)}
    {fields.length===0&&<p className="muted">Belum ada custom field aktif.</p>}
    {fields.length>1&&<p className="builder-order-hint"><GripVertical size={13}/> Drag custom field ke atas atau bawah. Urutan tersimpan otomatis dan dipakai di form registrasi.</p>}

    {archived.length>0&&<div className="archived-fields"><div className="builder-title-row"><h3>Field Diarsipkan</h3><span className="muted">{archived.length} field</span></div><p className="muted">Tidak tampil di form baru. Data lama tetap tersimpan dan dapat dilihat kembali di Data Pendaftaran.</p>{archived.map(f=><div className="field-row archived-field-row" key={f.id}><Archive size={17}/><div className="field-meta"><strong>{f.label}</strong><span>{typeLabels[f.field_type]||f.field_type} • ARCHIVED</span></div><button className="btn secondary compact-btn" onClick={()=>restoreField(f.id)}><RotateCcw size={14}/> Restore</button></div>)}</div>}
   </section>

   <section className="panel">
    <h3>Tambah Field</h3>
    <label>Label<input value={draft.label} onChange={e=>setDraft({...draft,label:e.target.value,field_key:slugify(e.target.value).replace(/-/g,'_')})}/></label>
    <label>Deskripsi / Helper Text<textarea rows="3" placeholder="Contoh: Upload bukti yang terlihat jelas." value={draft.description} onChange={e=>setDraft({...draft,description:e.target.value})}/></label>
    <label>Key<input value={draft.field_key} onChange={e=>setDraft({...draft,field_key:e.target.value.replace(/[^a-z0-9_]/g,'')})}/></label>
    <label>Type<select value={draft.field_type} onChange={e=>setDraft({...draft,field_type:e.target.value})}>{types.map(t=><option key={t} value={t}>{typeLabels[t]}</option>)}</select></label>
    {['dropdown','radio','checkbox'].includes(draft.field_type)&&<label>Options (pisahkan koma)<input value={draft.options} onChange={e=>setDraft({...draft,options:e.target.value})}/></label>}
    {draft.field_type==='conditional_choice'&&<div className="conditional-choice-builder"><div className="builder-note"><GitBranch size={16}/><span>Gunakan tepat 2 opsi. Setelah field dibuat, masing-masing opsi dapat dihubungkan ke satu target field.</span></div><label>Opsi 1<input placeholder="Contoh: Sekolah" value={draft.choice_a} onChange={e=>setDraft({...draft,choice_a:e.target.value})}/></label><label>Opsi 2<input placeholder="Contoh: Komunitas" value={draft.choice_b} onChange={e=>setDraft({...draft,choice_b:e.target.value})}/></label></div>}
    {draft.field_type==='file'&&<div className="file-rule-box"><FileUp size={18}/><div><strong>File Upload</strong><p>1 file per field • Maksimal 1 MB. Gambar akan dikompres otomatis jika diperlukan.</p><label>Allowed File<select value={draft.allowed_file_type} onChange={e=>setDraft({...draft,allowed_file_type:e.target.value})}><option value="image">Image only</option><option value="pdf">PDF only</option><option value="image_pdf">Image + PDF</option></select></label></div></div>}
    <ReferenceImageEditor value={draft.reference_image_data_url} busy={imageBusy==='draft'} onPick={file=>referenceImage(file,'draft')} onRemove={()=>setDraft({...draft,reference_image_data_url:null})}/>
    <label className="check"><input type="checkbox" checked={draft.required} onChange={e=>setDraft({...draft,required:e.target.checked})}/> Wajib diisi</label>
    <button className="btn primary wide" onClick={add}><Plus size={17}/> Tambah Field</button>
   </section>
  </div>
 </div>
}

function ReferenceImageEditor({value,busy,onPick,onRemove}){return <div className="reference-editor"><div><strong>Reference Image</strong><span>Opsional • otomatis dikecilkan untuk menjaga layout form.</span></div>{value&&<img src={value} alt="Reference"/>}<div className="button-row"><label className="btn secondary file-btn"><ImagePlus size={15}/>{busy?'Memproses...':value?'Ganti Gambar':'Upload Gambar'}<input type="file" accept="image/*" disabled={busy} onChange={e=>onPick(e.target.files?.[0])}/></label>{value&&<button type="button" className="btn secondary" onClick={onRemove}>Hapus Gambar</button>}</div></div>}
