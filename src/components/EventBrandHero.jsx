import { formatEventDate } from '../utils/format'
export default function EventBrandHero({event,eyebrow='REGISTRATION',compact=false}){
  if(!event)return null
  return <div className={`event-brand-hero ${compact?'compact':''} ${event.banner_data_url?'has-banner':''}`} style={event.banner_data_url?{backgroundImage:`linear-gradient(90deg,rgba(5,7,12,.72),rgba(5,7,12,.26)),url(${event.banner_data_url})`}:undefined}>
    <div className="event-brand-overlay">
      {event.logo_data_url&&<div className="event-brand-logo"><img src={event.logo_data_url} alt={`${event.name} logo`}/></div>}
      <div className="event-brand-copy"><div className="eyebrow">{eyebrow}</div><h1>{event.name}</h1><div className="event-date-badge">{formatEventDate(event.event_date)}</div></div>
    </div>
  </div>
}
