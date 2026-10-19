import { Moon,Sun } from 'lucide-react'
import { useEffect,useState } from 'react'
export default function ThemeToggle({storageKey='sena-theme',defaultTheme='dark'}){
  const [theme,setTheme]=useState(()=>localStorage.getItem(storageKey)||defaultTheme||'dark')
  useEffect(()=>{const saved=localStorage.getItem(storageKey);setTheme(saved||defaultTheme||'dark')},[storageKey,defaultTheme])
  useEffect(()=>{document.documentElement.dataset.theme=theme;localStorage.setItem(storageKey,theme)},[theme,storageKey])
  return <button className="icon-btn" onClick={()=>setTheme(theme==='dark'?'light':'dark')} title="Ganti tema">{theme==='dark'?<Sun size={18}/>:<Moon size={18}/>}</button>
}
