export default function PaginationBar({ pageSize, setPageSize, page, totalPages, setPage }) {
  return (
    <div className="pagination-bar">
      <div className="page-size">Tampilkan
        <select value={pageSize} onChange={(e) => { setPageSize(Number(e.target.value)); setPage(1) }}>
          {[20, 50, 100].map((n) => <option key={n} value={n}>{n}</option>)}
        </select>
      </div>
      <div className="page-controls">
        <button className="btn ghost" disabled={page <= 1} onClick={() => setPage(page - 1)}>Sebelumnya</button>
        <span>{page} / {Math.max(totalPages, 1)}</span>
        <button className="btn ghost" disabled={page >= totalPages} onClick={() => setPage(page + 1)}>Berikutnya</button>
      </div>
    </div>
  )
}
