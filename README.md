# GiftCircles (Expo + Supabase)

Quick start:
1) Create a Supabase project and copy the API URL + anon key.
2) In `app.json` under `expo.extra`, set `supabaseUrl` and `supabaseAnonKey`.
3) Run the SQL in `supabase_schema.sql` in Supabase SQL editor.
4) Install deps and run:
   ```bash
   npm install
   npm run start
   ```
5) Sign up, create an event, share the join code, create lists & items, claim items.

See the in‑app screens for flows. RLS policies hide claims from list recipients.
