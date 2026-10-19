import { createClient } from '@supabase/supabase-js'
const BUCKET='registration-files'
export default async function handler(req,res){
  if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'})
  const url=process.env.VITE_SUPABASE_URL||process.env.SUPABASE_URL
  const key=process.env.SUPABASE_SERVICE_ROLE_KEY
  if(!url||!key)return res.status(500).json({error:'Server file access belum dikonfigurasi.'})
  const {secret,path}=req.body||{}
  if(!secret||!path||typeof path!=='string')return res.status(400).json({error:'Request tidak valid.'})
  const supabase=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}})
  const {data:ok,error:verifyError}=await supabase.rpc('v3_admin_verify',{p_secret:secret})
  if(verifyError||!ok)return res.status(401).json({error:'Admin session tidak valid.'})
  if(path.includes('..')||path.startsWith('/'))return res.status(400).json({error:'Path file tidak valid.'})
  const {data,error}=await supabase.storage.from(BUCKET).createSignedUrl(path,90)
  if(error||!data?.signedUrl)return res.status(404).json({error:'File tidak ditemukan.'})
  return res.status(200).json({url:data.signedUrl})
}
