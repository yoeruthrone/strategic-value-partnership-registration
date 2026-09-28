export default function DataTable({ columns, rows, sort, onSort, emptyText = 'Belum ada data.' }) {
  return (
    <div className="table-wrap glass">
      <table>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} onClick={() => c.sortable !== false && onSort?.(c.key)} className={c.sortable === false ? '' : 'sortable'}>
                <span>{c.label}</span>
                {sort?.key === c.key ? <span className="sort-indicator">{sort.dir === 'asc' ? '↑' : '↓'}</span> : null}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr><td colSpan={columns.length} className="empty-cell">{emptyText}</td></tr>
          ) : rows.map((row, idx) => (
            <tr key={row.id || idx}>
              {columns.map((c) => <td key={c.key}>{c.render ? c.render(row, idx) : row[c.key]}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
