# Committee Manager Web

Responsive MERN companion for the Committee Manager Flutter app.

## Run locally

```bash
npm install
npm run dev
```

The Vite client runs on `5173`; the Express API runs on `5000`. If `MONGODB_URI` is not configured, the API uses the included demo data so the product remains usable for previews. Add the URI from `.env.example` to connect MongoDB.

## Included workflows

- Dashboard with collected/outstanding totals and progress
- Searchable committee workspace
- Create committee flow backed by Express
- Recent collections and member payout context
- Responsive navigation designed for desktop and mobile
- Framer Motion transitions and micro-interactions
