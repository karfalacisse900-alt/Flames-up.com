import { Hono } from 'hono';
import type { Env } from '../types';
import { getAuthUser } from '../lib/auth';

export const placesRoutes = new Hono<{ Bindings: Env }>();

placesRoutes.get('/nearby', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const lat = c.req.query('lat') || '40.7128';
  const lng = c.req.query('lng') || '-74.006';
  const type = c.req.query('type') || 'restaurant';
  const radius = c.req.query('radius') || '5000';
  const keyword = c.req.query('keyword') || '';

  let url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=${radius}&type=${type}&key=${c.env.GOOGLE_MAPS_API_KEY}`;
  if (keyword) url += `&keyword=${encodeURIComponent(keyword)}`;

  const res = await fetch(url);
  const data: any = await res.json();

  const places = (data.results || []).map((p: any) => ({
    place_id: p.place_id,
    name: p.name,
    vicinity: p.vicinity,
    rating: p.rating,
    user_ratings_total: p.user_ratings_total,
    open_now: p.opening_hours?.open_now,
    photo_url: p.photos?.[0]
      ? `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${p.photos[0].photo_reference}&key=${c.env.GOOGLE_MAPS_API_KEY}`
      : null,
    lat: p.geometry?.location?.lat,
    lng: p.geometry?.location?.lng,
    types: p.types,
  }));

  return c.json(places);
});

placesRoutes.get('/:placeId', async (c) => {
  const user = await getAuthUser(c);
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const placeId = c.req.param('placeId');
  const fields = 'name,formatted_address,formatted_phone_number,rating,user_ratings_total,reviews,photos,opening_hours,website,price_level,types,geometry,url';
  const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${placeId}&fields=${fields}&key=${c.env.GOOGLE_MAPS_API_KEY}`;

  const res = await fetch(url);
  const data: any = await res.json();
  const r = data.result;
  if (!r) return c.json({ error: 'Place not found' }, 404);

  return c.json({
    place_id: placeId,
    name: r.name,
    address: r.formatted_address,
    phone: r.formatted_phone_number,
    rating: r.rating,
    user_ratings_total: r.user_ratings_total,
    website: r.website,
    google_maps_url: r.url,
    price_level: r.price_level,
    types: r.types,
    lat: r.geometry?.location?.lat,
    lng: r.geometry?.location?.lng,
    open_now: r.opening_hours?.open_now,
    hours: r.opening_hours?.weekday_text,
    photos: (r.photos || []).slice(0, 6).map((p: any) =>
      `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=${p.photo_reference}&key=${c.env.GOOGLE_MAPS_API_KEY}`
    ),
    reviews: (r.reviews || []).slice(0, 5).map((rev: any) => ({
      author: rev.author_name,
      rating: rev.rating,
      text: rev.text,
      time: rev.relative_time_description,
      profile_photo: rev.profile_photo_url,
    })),
  });
});
