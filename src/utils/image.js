const MB=1024*1024
const loadImage=(file)=>new Promise((resolve,reject)=>{const src=URL.createObjectURL(file);const img=new Image();img.onload=()=>resolve({img,src});img.onerror=()=>{URL.revokeObjectURL(src);reject(new Error('Gambar tidak dapat dibaca.'))};img.src=src})
const canvasBlob=(canvas,type='image/webp',quality=.82)=>new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Gambar gagal diproses.')),type,quality))
export async function imageFileToDataUrl(file,{maxWidth=1600,maxHeight=900,quality=.82,maxInputMB=8}={}){
  if(!file)return null
  if(!file.type.startsWith('image/'))throw new Error('File harus berupa gambar.')
  if(file.size>maxInputMB*MB)throw new Error(`Ukuran file maksimal ${maxInputMB} MB sebelum optimasi.`)
  const {img,src}=await loadImage(file)
  try{
    const ratio=Math.min(1,maxWidth/img.width,maxHeight/img.height)
    const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.width*ratio));canvas.height=Math.max(1,Math.round(img.height*ratio))
    canvas.getContext('2d').drawImage(img,0,0,canvas.width,canvas.height)
    return canvas.toDataURL('image/webp',quality)
  }finally{URL.revokeObjectURL(src)}
}
export async function prepareRegistrationImage(file,{maxBytes=MB,maxWidth=1800,maxHeight=1800}={}){
  if(!file?.type?.startsWith('image/'))throw new Error('File harus berupa gambar.')
  if(file.size<=maxBytes)return file
  if(file.size>8*MB)throw new Error('Ukuran gambar terlalu besar. Maksimal 8 MB sebelum kompresi.')
  const {img,src}=await loadImage(file)
  try{
    let ratio=Math.min(1,maxWidth/img.width,maxHeight/img.height)
    let quality=.82
    for(let i=0;i<7;i++){
      const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.width*ratio));canvas.height=Math.max(1,Math.round(img.height*ratio));canvas.getContext('2d').drawImage(img,0,0,canvas.width,canvas.height)
      const blob=await canvasBlob(canvas,'image/webp',quality)
      if(blob.size<=maxBytes)return new File([blob],`${file.name.replace(/\.[^.]+$/,'')}.webp`,{type:'image/webp'})
      quality=Math.max(.48,quality-.08);ratio*=.86
    }
    throw new Error('Gambar tidak dapat diperkecil sampai 1 MB. Gunakan gambar dengan resolusi lebih kecil.')
  }finally{URL.revokeObjectURL(src)}
}
export const bytesLabel=(n=0)=>n<1024?`${n} B`:n<MB?`${Math.ceil(n/1024)} KB`:`${(n/MB).toFixed(2)} MB`
