export function normalizeText(value = '') {
  return value
    .toString()
    .trim()
    .toUpperCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Z0-9\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

export function normalizePhone(value = '') {
  return value.toString().replace(/\D/g, '')
}

export function formatWitaTime(iso) {
  if (!iso) return '-'
  return new Intl.DateTimeFormat('id-ID', {
    timeZone: 'Asia/Makassar',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(new Date(iso))
}
