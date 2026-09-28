import { Navigate, Route, Routes } from 'react-router-dom'
import RegisterPage from './pages/RegisterPage'
import DashboardLayout from './pages/DashboardLayout'
import DashboardPage from './pages/DashboardPage'
import ParticipantsPage from './pages/ParticipantsPage'
import PartnersPage from './pages/PartnersPage'

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/register" replace />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route path="/internal/:secret" element={<DashboardLayout />}>
        <Route index element={<DashboardPage />} />
        <Route path="participants" element={<ParticipantsPage />} />
        <Route path="partners" element={<PartnersPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/register" replace />} />
    </Routes>
  )
}
