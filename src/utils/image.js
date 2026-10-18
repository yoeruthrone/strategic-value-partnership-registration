export async function imageFileToDataUrl(file,{maxWidth=1600,maxHeight=900,quality=.82}={}){
  if(!file)return null
  if(!file.type.startsWith('image/'))throw new Error('File harus berupa gambar.')
  if(file.size>8*1024*1024)throw new Error('Ukuran file maksimal 8 MB sebelum optimasi.')
  const src=URL.createObjectURL(file)
  try{
    const img=await new Promise((resolve,reject)=>{const el=new Image();el.onload=()=>resolve(el);el.onerror=()=>reject(new Error('Gambar tidak dapat dibaca.'));el.src=src})
    const ratio=Math.min(1,maxWidth/img.width,maxHeight/img.height)
    const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.width*ratio));canvas.height=Math.max(1,Math.round(img.height*ratio))
    const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0,canvas.width,canvas.height)
    return canvas.toDataURL('image/webp',quality)
  }finally{URL.revokeObjectURL(src)}
}
