# V3.1.3 Patch

Fixes two UI regressions from the V3.1.2 mobile containment pass:

1. QR scanner preview
   - removes the CSS rule that forced html5-qrcode's internal canvas to display as a second/mirrored frame
   - restores a single camera viewport with html5-qrcode's QR scan box
   - uses responsive qrbox sizing
   - cleans up/stops the previous scanner instance before restarting

2. Admin navigation
   - desktop/tablet sidebar is fixed to the viewport
   - main content scrolls independently beside it
   - on mobile the navigation becomes a fixed top strip
   - theme/logout controls remain available while content scrolls

No SQL migration is required.
