type DiscoverCache = {
  stories: any[];
  notes: any[];
  updatedAt: number;
};

let cache: DiscoverCache = {
  stories: [],
  notes: [],
  updatedAt: 0,
};

export function getCachedDiscover() {
  return cache;
}

export function cacheDiscoverStories(stories: any[]) {
  cache = {
    ...cache,
    stories: Array.isArray(stories) ? stories : [],
    updatedAt: Date.now(),
  };
}

export function cacheDiscoverNotes(notes: any[]) {
  cache = {
    ...cache,
    notes: Array.isArray(notes) ? notes : [],
    updatedAt: Date.now(),
  };
}
