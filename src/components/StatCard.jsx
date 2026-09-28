export default function StatCard({ label, value, icon, onClick }) {
  return (
    <button
      type="button"
      className={`glass stat-card ${onClick ? 'clickable' : ''}`}
      onClick={onClick}
      disabled={!onClick}
    >
      <div className="stat-icon">{icon}</div>
      <div>
        <div className="muted small">{label}</div>
        <div className="stat-value">{value}</div>
      </div>
    </button>
  )
}
