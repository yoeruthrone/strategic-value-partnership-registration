import { NavLink, Outlet, useParams } from 'react-router-dom'
import { LayoutDashboard, Users, Building2, ScanLine } from 'lucide-react'
import LogoMark from '../components/LogoMark'

export default function DashboardLayout() {
  const { secret } = useParams()
  return <div className="dashboard-shell">
    <aside className="sidebar glass">
      <div className="brand-row"><LogoMark/><div><strong>EVENT</strong><span>REGISTRATION</span></div></div>
      <nav>
        <NavLink end to={`/internal/${secret}`}><LayoutDashboard size={19}/>Dashboard</NavLink>
        <NavLink to={`/internal/${secret}/participants`}><Users size={19}/>Total Peserta</NavLink>
        <NavLink to={`/internal/${secret}/partners`}><Building2 size={19}/>Total Mitra</NavLink>
        <NavLink to={`/internal/${secret}/scanner`}><ScanLine size={19}/>Scan QR</NavLink>
      </nav>
    </aside>
    <div className="dashboard-content"><Outlet context={{secret}}/></div>
  </div>
}
