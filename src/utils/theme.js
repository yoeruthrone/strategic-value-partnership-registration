export const DEFAULT_EVENT_THEME={primary:'#009FEE',accent:'#EE00C6',secondary:'#4F00EE',defaultTheme:'dark'}
export const eventThemeStyle=(event={},extra={})=>({
  '--event-primary':event.theme_primary||DEFAULT_EVENT_THEME.primary,
  '--event-accent':event.theme_accent||DEFAULT_EVENT_THEME.accent,
  '--event-secondary':event.theme_secondary||DEFAULT_EVENT_THEME.secondary,
  '--blue':event.theme_primary||DEFAULT_EVENT_THEME.primary,
  '--pink':event.theme_accent||DEFAULT_EVENT_THEME.accent,
  '--purple':event.theme_secondary||DEFAULT_EVENT_THEME.secondary,
  ...extra
})
export const eventThemeStorageKey=(event)=>`sena-theme:event:${event?.slug||event?.id||'public'}`
