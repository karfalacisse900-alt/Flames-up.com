import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { authRoutes } from './routes/auth';
import { postRoutes } from './routes/posts';
import { feedRoutes } from './routes/feed';
import { profileRoutes } from './routes/profile';
import { uploadRoutes } from './routes/upload';
import { placesRoutes } from './routes/places';
import { socialRoutes } from './routes/social';
import type { Env } from './types';

const app = new Hono<{ Bindings: Env }>();

app.use('/*', cors({
  origin: '*',
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));

app.get('/api/health', (c) => c.json({ status: 'ok', service: 'flames-up-api' }));

app.route('/api/auth', authRoutes);
app.route('/api/posts', postRoutes);
app.route('/api', feedRoutes);
app.route('/api/profile', profileRoutes);
app.route('/api/upload', uploadRoutes);
app.route('/api/places', placesRoutes);
app.route('/api', socialRoutes);

export default app;
