import * as XLSX from 'xlsx'
import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'
import { formatWitaTime } from './normalize'

export function exportParticipantsExcel(rows, filename = 'peserta-event.xlsx') {
  const data = rows.map((r, i) => ({
    No: i + 1,
    Waktu: formatWitaTime(r.created_at),
    Nama: r.full_name,
    'No. Telepon': r.phone || '-',
    'Nama Mitra': r.partner_name,
    Jabatan: r.position,
  }))
  const ws = XLSX.utils.json_to_sheet(data)
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Seluruh Peserta')
  XLSX.writeFile(wb, filename)
}

export function exportParticipantsPdf(rows, eventName = 'Event', filename = 'peserta-event.pdf') {
  const doc = new jsPDF({ orientation: 'landscape' })
  doc.setFontSize(16)
  doc.text(`Laporan Peserta - ${eventName}`, 14, 16)
  autoTable(doc, {
    startY: 22,
    head: [['No', 'Waktu', 'Nama', 'No. Telepon', 'Nama Mitra', 'Jabatan']],
    body: rows.map((r, i) => [
      i + 1,
      formatWitaTime(r.created_at),
      r.full_name,
      r.phone || '-',
      r.partner_name,
      r.position,
    ]),
    styles: { fontSize: 8 },
  })
  doc.save(filename)
}
