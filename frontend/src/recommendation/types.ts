export interface RecommendationItem {
  id: string;
  authorId?: string;
  category?: string;
  content?: string;
  location?: string;
  createdAtMs: number;
  likes: number;
  comments: number;
  shares: number;
  saves: number;
  impressions: number;
  lat?: number;
  lng?: number;
  original: any;
}

export interface RecommendationContext {
  userId?: string;
  interests: string[];
  nowMs: number;
  userLat?: number;
  userLng?: number;
}

export interface RecommendationOptions {
  maxItems?: number;
  lambda?: number;
  halfLifeHours?: number;
}
