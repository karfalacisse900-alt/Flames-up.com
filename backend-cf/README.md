# Flames-Up API — Cloudflare Workers

Production-ready backend using **Hono** router, **Cloudflare D1** (SQLite), **Cloudflare Images**, and **Cloudflare Stream**.

## Structure

```
backend-cf/
├── wrangler.toml          # Cloudflare config (D1, KV bindings)
├── package.json           # Dependencies (hono, jose)
├── tsconfig.json          # TypeScript config
├── migrations/
│   └── 0001_init.sql      # D1 database schema (13 tables)
└── src/
    └── index.ts           # Complete Hono API (all endpoints)
```

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Create D1 database:**
   ```bash
   wrangler d1 create flames-up-db
   ```
   Copy the `database_id` into `wrangler.toml`.

3. **Create KV namespace:**
   ```bash
   wrangler kv namespace create "KV"
   ```
   Copy the `id` into `wrangler.toml`.

4. **Run migrations:**
   ```bash
   # Local development
   wrangler d1 execute flames-up-db --file=./migrations/0001_init.sql --local

   # Production
   wrangler d1 execute flames-up-db --file=./migrations/0001_init.sql --remote
   ```

5. **Set environment variables in `wrangler.toml`:**
   - `JWT_SECRET` — A random secret for JWT signing
   - `CLOUDFLARE_ACCOUNT_ID` — Your Cloudflare account ID
   - `CLOUDFLARE_IMAGES_TOKEN` — API token with Images access
   - `CLOUDFLARE_STREAM_TOKEN` — API token with Stream access
   - `GOOGLE_MAPS_API_KEY` — For Places API proxy

6. **Deploy:**
   ```bash
   wrangler deploy
   ```

## API Endpoints

### Auth
- `POST /api/auth/register` — Sign up
- `POST /api/auth/login` — Sign in (returns JWT)
- `GET /api/auth/me` — Current user

### Posts (with Check-In support)
- `POST /api/posts` — Create post (lifestyle / check_in / question)
- `GET /api/posts/feed` — Feed (paginated)
- `GET /api/posts/nearby-feed` — Location-prioritized feed
- `GET /api/posts/:id` — Single post
- `POST /api/posts/:id/like` — Toggle like
- `DELETE /api/posts/:id` — Delete own post
- `POST /api/posts/:id/comments` — Add comment
- `GET /api/posts/:id/comments` — List comments

### Uploads (Direct to Cloudflare)
- `POST /api/upload/image-direct` — Get CF Images upload URL
- `POST /api/upload/video-direct` — Get CF Stream upload URL

### Users, Statuses, Messages, Library, Friends, Places, Discover
All endpoints fully implemented. See `src/index.ts` for details.

## Image Upload Flow (Cloudflare Images)

1. Frontend calls `POST /api/upload/image-direct` → gets `upload_url` + `image_id`
2. Frontend uploads image directly to `upload_url`
3. Frontend sends `image_id` in `POST /api/posts`

No base64. No file proxy. Direct upload to Cloudflare edge.
