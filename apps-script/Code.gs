/**
 * Strategic Value Partnership - Live Registration Spreadsheet
 * Google Apps Script (bound to ONE Google Spreadsheet)
 *
 * Required Script Properties:
 * SUPABASE_URL
 * SUPABASE_ANON_KEY
 * DASHBOARD_SECRET
 * SYNC_TOKEN
 * EVENT_NAME (optional; default Strategic Value Partnership)
 * SPREADSHEET_ID (created automatically by setupSpreadsheet when run from bound spreadsheet)
 */

const TZ = 'Asia/Makassar';
const SHEET_DASHBOARD = 'Dashboard';
const SHEET_PARTICIPANTS = 'Total Peserta';
const SHEET_PARTNERS = 'Total Mitra';

function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, service: 'registration-spreadsheet-sync' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    const props = PropertiesService.getScriptProperties();
    const expectedToken = props.getProperty('SYNC_TOKEN') || '';
    const suppliedToken = (e && e.parameter && e.parameter.token) ? String(e.parameter.token) : '';

    if (!expectedToken || suppliedToken !== expectedToken) {
      return jsonResponse_({ ok: false, error: 'unauthorized' });
    }

    const result = syncAllData();
    return jsonResponse_({ ok: true, ...result });
  } catch (err) {
    console.error(err);
    return jsonResponse_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

/**
 * Run once manually from Apps Script after setting Script Properties.
 * Creates/repairs the three tabs and stores the bound spreadsheet ID.
 */
function setupSpreadsheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) throw new Error('Buka Apps Script dari Google Spreadsheet (Extensions > Apps Script), lalu jalankan setupSpreadsheet().');

  PropertiesService.getScriptProperties().setProperty('SPREADSHEET_ID', ss.getId());
  ensureSheets_(ss);
  const result = syncAllData();
  SpreadsheetApp.flush();
  return result;
}

/** Manual recovery/full refresh. */
function syncAllData() {
  const props = PropertiesService.getScriptProperties();
  const spreadsheetId = requiredProperty_(props, 'SPREADSHEET_ID');
  const eventName = props.getProperty('EVENT_NAME') || 'Strategic Value Partnership';

  const snapshot = fetchDashboardSnapshot_(props);
  const participants = Array.isArray(snapshot.participants) ? snapshot.participants : [];
  const partnerRows = buildPartners_(participants);

  const ss = SpreadsheetApp.openById(spreadsheetId);
  ensureSheets_(ss);
  writeDashboard_(ss.getSheetByName(SHEET_DASHBOARD), eventName, snapshot, partnerRows);
  writeParticipants_(ss.getSheetByName(SHEET_PARTICIPANTS), participants);
  writePartners_(ss.getSheetByName(SHEET_PARTNERS), partnerRows);
  SpreadsheetApp.flush();

  return {
    participant_count: participants.length,
    partner_count: partnerRows.length,
    updated_at_wita: Utilities.formatDate(new Date(), TZ, 'dd/MM/yyyy HH:mm:ss')
  };
}

/** Optional fallback. Run once if you want a periodic backup sync every 5 minutes. */
function installFallbackTrigger() {
  removeFallbackTriggers();
  ScriptApp.newTrigger('syncAllData').timeBased().everyMinutes(5).create();
}

function removeFallbackTriggers() {
  ScriptApp.getProjectTriggers().forEach((trigger) => {
    if (trigger.getHandlerFunction() === 'syncAllData') ScriptApp.deleteTrigger(trigger);
  });
}

function fetchDashboardSnapshot_(props) {
  const baseUrl = requiredProperty_(props, 'SUPABASE_URL').replace(/\/$/, '');
  const anonKey = requiredProperty_(props, 'SUPABASE_ANON_KEY');
  const dashboardSecret = requiredProperty_(props, 'DASHBOARD_SECRET');
  const url = baseUrl + '/rest/v1/rpc/dashboard_snapshot';

  const response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    muteHttpExceptions: true,
    headers: {
      apikey: anonKey,
      Authorization: 'Bearer ' + anonKey
    },
    payload: JSON.stringify({ p_secret: dashboardSecret })
  });

  const status = response.getResponseCode();
  const body = response.getContentText();
  if (status < 200 || status >= 300) {
    throw new Error('Supabase sync gagal (' + status + '): ' + body);
  }
  return JSON.parse(body || '{}');
}

function buildPartners_(participants) {
  const map = new Map();
  participants.forEach((p) => {
    const name = String(p.partner_name || '').trim();
    if (!name) return;
    if (!map.has(name)) map.set(name, []);
    map.get(name).push(p);
  });

  return Array.from(map.entries())
    .map(([partner_name, rows]) => ({ partner_name, participant_count: rows.length }))
    .sort((a, b) => (b.participant_count - a.participant_count) || a.partner_name.localeCompare(b.partner_name));
}

function ensureSheets_(ss) {
  [SHEET_DASHBOARD, SHEET_PARTICIPANTS, SHEET_PARTNERS].forEach((name) => {
    if (!ss.getSheetByName(name)) ss.insertSheet(name);
  });
}

function writeDashboard_(sheet, eventName, snapshot, partners) {
  sheet.clear();
  const now = Utilities.formatDate(new Date(), TZ, 'dd/MM/yyyy HH:mm:ss') + ' WITA';
  const values = [
    ['STRATEGIC VALUE PARTNERSHIP - REGISTRATION REPORT', ''],
    ['Nama Event', eventName],
    ['Total Peserta', Number(snapshot.total_participants || 0)],
    ['Total Mitra', Number(snapshot.total_partners || partners.length || 0)],
    ['Last Update', now]
  ];
  sheet.getRange(1, 1, values.length, 2).setValues(values);
  sheet.getRange('A1:B1').merge().setFontWeight('bold').setFontSize(14).setBackground('#10182F').setFontColor('#FFFFFF');
  sheet.getRange('A2:A5').setFontWeight('bold').setBackground('#EAF2FF');
  sheet.getRange('B2:B5').setBackground('#F8FAFF');
  sheet.setFrozenRows(1);
  sheet.setColumnWidth(1, 180);
  sheet.setColumnWidth(2, 320);
}

function writeParticipants_(sheet, participants) {
  if (sheet.getFilter()) sheet.getFilter().remove();
  sheet.clear();
  const header = ['No', 'Waktu WITA', 'Nama Lengkap', 'No. Telp', 'Nama Mitra', 'Jabatan'];
  const rows = participants.map((p, index) => [
    index + 1,
    formatWita_(p.created_at),
    p.full_name || '',
    p.phone || '-',
    p.partner_name || '',
    p.position || ''
  ]);

  sheet.getRange(1, 1, 1, header.length).setValues([header]);
  if (rows.length) sheet.getRange(2, 1, rows.length, header.length).setValues(rows);
  styleDataSheet_(sheet, header.length, rows.length);
}

function writePartners_(sheet, partners) {
  if (sheet.getFilter()) sheet.getFilter().remove();
  sheet.clear();
  const header = ['No', 'Nama Mitra', 'Jumlah Peserta'];
  const rows = partners.map((p, index) => [index + 1, p.partner_name, p.participant_count]);

  sheet.getRange(1, 1, 1, header.length).setValues([header]);
  if (rows.length) sheet.getRange(2, 1, rows.length, header.length).setValues(rows);
  styleDataSheet_(sheet, header.length, rows.length);
}

function styleDataSheet_(sheet, columnCount, dataRowCount) {
  const header = sheet.getRange(1, 1, 1, columnCount);
  header.setFontWeight('bold').setBackground('#10182F').setFontColor('#FFFFFF');
  sheet.setFrozenRows(1);

  if (dataRowCount > 0) {
    sheet.getRange(1, 1, dataRowCount + 1, columnCount).createFilter();
    sheet.getRange(2, 1, dataRowCount, columnCount).setVerticalAlignment('middle');
  }

  sheet.autoResizeColumns(1, columnCount);
  for (let c = 1; c <= columnCount; c++) {
    const width = sheet.getColumnWidth(c);
    sheet.setColumnWidth(c, Math.min(Math.max(width, 90), 300));
  }
}

function formatWita_(iso) {
  if (!iso) return '';
  return Utilities.formatDate(new Date(iso), TZ, 'HH:mm:ss');
}

function requiredProperty_(props, key) {
  const value = props.getProperty(key);
  if (!value) throw new Error('Script Property ' + key + ' belum diisi.');
  return value;
}

function jsonResponse_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
