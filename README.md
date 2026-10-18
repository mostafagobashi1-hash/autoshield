# AutoShield — Starter MVP

## What is included
- `index.html`: Arabic RTL browser-based prototype.
- `schema.sql`: PostgreSQL starter schema for the production backend.
- EGP currency, initial services, customers/vehicles, work orders, service list, basic inventory, print view, JSON backup/restore.
- Responsive layout for desktop and mobile.

## Run the prototype
1. Extract the ZIP.
2. Open `index.html` in a modern browser (Chrome or Edge recommended).
3. Data is saved in that browser's local storage on that device.

No server is required for this prototype. It is not yet a multi-user or cloud-synced system.

## Important limitations
- Do not store real sensitive/customer data in this prototype as the only copy.
- No authentication, role-based authorization, cloud sync, offline-to-cloud conflict resolution, payment ledger, detailed inventory consumption, warranty certificates, or production invoice numbering yet.
- The print function prints a work-order sheet. A4/thermal receipt layouts should be finalized against the actual printer and paper width.
- Export a JSON backup regularly while testing.

## Recommended production architecture
- Frontend: Next.js + TypeScript (Arabic RTL/PWA).
- API/backend: Next.js server actions/API or a separate Node service.
- Database: PostgreSQL.
- Authentication: secure server-side sessions and role-based access control.
- File storage: private object storage for intake/before/after photos.
- Offline: service worker + IndexedDB outbox; synchronize changes with server using stable IDs, idempotency keys, and conflict handling.
- Hosting: managed application host + managed PostgreSQL, HTTPS, scheduled backups and restore drills.

## Production milestones
1. Authentication, users, roles, audit logging.
2. Customer/vehicle records and work-order workflow.
3. Invoice/payment ledger and receipt templates.
4. Inventory movements, recipe/consumption per service, waste.
5. Warranty certificates, photos, warranty claims.
6. Offline queue and cloud synchronization.
7. Reports, automated tests, backups, deployment.

## Database
Review `schema.sql` with a developer before production deployment. Set database credentials via environment variables, never hardcode secrets. Add database migrations and test restore procedures.
