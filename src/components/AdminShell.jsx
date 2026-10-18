import { NavLink,Outlet,useNavigate } from 'react-router-dom'
import { CalendarDays,LogOut,Plus } from 'lucide-react'
import Brand from './Brand';import ThemeToggle from './ThemeToggle'
export default function AdminShell(){const nav=useNavigate();return <div className="admin-shell"><aside className="sidebar"><Brand compact/><nav><NavLink to="/admin/events"><CalendarDays size={18}/>Events</NavLink></nav><div className="sidebar-bottom"><ThemeToggle/><button className="icon-btn" onClick={()=>{sessionStorage.removeItem('sena_admin_secret');nav('/admin')}}><LogOut size={18}/></button></div></aside><main className="admin-main"><Outlet/></main></div>}
