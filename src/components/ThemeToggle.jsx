import { Moon,Sun } from 'lucide-react'
import { useEffect,useState } from 'react'
export default function ThemeToggle(){const [theme,setTheme]=useState(()=>localStorage.getItem('sena-theme')||'dark');useEffect(()=>{document.documentElement.dataset.theme=theme;localStorage.setItem('sena-theme',theme)},[theme]);return <button className="icon-btn" onClick={()=>setTheme(theme==='dark'?'light':'dark')} title="Ganti tema">{theme==='dark'?<Sun size={18}/>:<Moon size={18}/>}</button>}
