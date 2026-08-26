export type AuraCommunityFeedCursor = {
  createdAt: string;
  id: string;
};

export type AuraCommunityProjectedItem<T> = {
  sourceId: string;
  item: T;
};

export function normalizeAuraCommunityCity(value: unknown): string;
export function encodeAuraCommunityFeedCursor(cursor: AuraCommunityFeedCursor | null | undefined): string;
export function decodeAuraCommunityFeedCursor(value: unknown): AuraCommunityFeedCursor | null;
export function auraCommunityFeedCursorFilter(cursor: AuraCommunityFeedCursor | null | undefined): string;
export function auraCommunityFeedRowCursor(row: unknown): AuraCommunityFeedCursor | null;

export function collectAuraCommunityCursorPage<Row, Item>(options: {
  limit: number;
  chunkSize?: number;
  cursor?: AuraCommunityFeedCursor | null;
  readChunk: (cursor: AuraCommunityFeedCursor | null, limit: number) => Promise<Row[]>;
  rowCursor: (row: Row) => AuraCommunityFeedCursor | null;
  projectVisible: (rows: Row[]) => Promise<Array<AuraCommunityProjectedItem<Item>>>;
}): Promise<{
  items: Item[];
  nextCursor: AuraCommunityFeedCursor | null;
  hasMore: boolean;
}>;
