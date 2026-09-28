export default function DuplicateModal({ open, result, onCancel, onContinue }) {
  if (!open) return null
  return (
    <div className="modal-backdrop">
      <div className="modal glass strong-glow">
        <div className="warning-icon">!</div>
        <h3>DATA SERUPA DITEMUKAN</h3>
        <p className="muted">Sistem menemukan data yang kemungkinan sudah pernah didaftarkan.</p>
        {result?.name_partner_matches?.length > 0 && (
          <div className="duplicate-box">
            <strong>Nama + Nama Mitra sama</strong>
            {result.name_partner_matches.map((name) => <div key={name}>{name}</div>)}
          </div>
        )}
        {result?.phone_match && (
          <div className="duplicate-box"><strong>Nomor telepon sudah pernah digunakan.</strong></div>
        )}
        <p>Anda tetap dapat melanjutkan bila data tersebut memang benar.</p>
        <div className="modal-actions">
          <button className="btn ghost" onClick={onCancel}>Kembali & Periksa</button>
          <button className="btn primary" onClick={onContinue}>Tetap Daftarkan</button>
        </div>
      </div>
    </div>
  )
}
