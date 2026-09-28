export default function Loading({ label = 'Memuat...' }) {
  return <div className="loading"><span className="spinner" />{label}</div>
}
