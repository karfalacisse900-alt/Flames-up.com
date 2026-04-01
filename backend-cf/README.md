# Flames-Up Cloudflare Workers Backend

A production-ready backend for Flames-Up built entirely on Cloudflare's edge platform.

## Architecture

- **Cloudflare Workers** — API server (TypeScript + Hono)
- **Cloudflare D1** — SQLite database at the edge
- **Cloudflare KV** — Session store & rate limiting
- **Cloudflare Images** — Image upload/delivery for posts and avatars
- **Cloudflare Stream** — Video upload/playback for posts

## Deployment

### 1. Create Resources

```bash
# Create D1 database
wrangler d1 create flames-up-db
# Copy the database_id to wrangler.toml

# Create KV namespace
wrangler kv namespace create KV
# Copy the id to wrangler.toml
```

### 2. Run Migrations

```bash
wrangler d1 execute flames-up-db --file=./migrations/0001_init.sql
```

### 3. Set Secrets

```bash
wrangler secret put JWT_SECRET
wrangler secret put CF_API_TOKEN
wrangler secret put CF_ACCOUNT_ID
wrangler secret put GOOGLE_MAPS_API_KEY
```

### 4. Deploy

```bash
npm install
npm run deploy
```

## Photo Upload Flow

1. Frontend calls `POST /api/upload/image-direct`
2. Worker returns `{ upload_url, image_id, delivery_url }` from Cloudflare Images
3. Frontend uploads the file directly to `upload_url`
4. Frontend sends `POST /api/posts` with `image_ids: [image_id]`
5. Images display via `https://imagedelivery.net/DY-IgVdOm-0zb0K5ZFnpKA/{image_id}/public`

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/auth/signup | Register |
| POST | /api/auth/login | Login |
| GET | /api/auth/me | Current user |
| GET | /api/feed | Feed posts |
| POST | /api/posts | Create post |
| GET | /api/posts/:id | Get post |
| POST | /api/posts/:id/like | Like/unlike |
| POST | /api/posts/:id/comment | Add comment |
| GET | /api/profile/:username | User profile |
| POST | /api/upload/image-direct | CF Images direct upload |
| POST | /api/upload/video-direct | CF Stream direct upload |
| GET | /api/places/nearby | Google Places nearby |
| GET | /api/places/:placeId | Place details |
| POST | /api/follow/:userId | Follow/unfollow |
| GET | /api/notifications | User notifications |
| POST | /api/reports | Report content |
| POST | /api/friends/request/:userId | Send friend request |
| POST | /api/friends/accept/:requestId | Accept request |
| GET | /api/library/liked | Liked posts |
| POST | /api/library/save/:postId | Save post |

## Frontend Configuration

Set `VITE_API_URL` (or `EXPO_PUBLIC_API_URL`) to your Worker URL:

```env
VITE_API_URL=https://flames-up-api.your-subdomain.workers.dev
```
