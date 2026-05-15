import { create } from 'zustand';

type OptionalBool = boolean | undefined;

export type PostInteractionState = {
  liked?: boolean;
  likesCount?: number;
  saved?: boolean;
  savesCount?: number;
  following?: boolean;
  userId?: string;
};

type SocialState = {
  posts: Record<string, PostInteractionState>;
  followedUserIds: Record<string, boolean>;
  hydratePosts: (posts: any[], currentUserId?: string | null) => void;
  setPostLiked: (postId: string, liked: boolean, likesCount?: number) => void;
  setPostSaved: (postId: string, saved: boolean, savesCount?: number) => void;
  setUserFollowing: (userId: string, following: boolean) => void;
};

function hasOwn(value: any, key: string) {
  return value && Object.prototype.hasOwnProperty.call(value, key);
}

function boolFromPost(post: any, keys: string[]): OptionalBool {
  for (const key of keys) {
    if (hasOwn(post, key)) return !!post[key];
  }
  return undefined;
}

function numberOrUndefined(value: unknown): number | undefined {
  const next = Number(value);
  return Number.isFinite(next) ? Math.max(0, next) : undefined;
}

function sameValue(a: unknown, b: unknown) {
  return a === b || (a === undefined && b === undefined);
}

function samePostState(a: PostInteractionState = {}, b: PostInteractionState = {}) {
  return sameValue(a.userId, b.userId)
    && sameValue(a.liked, b.liked)
    && sameValue(a.likesCount, b.likesCount)
    && sameValue(a.saved, b.saved)
    && sameValue(a.savesCount, b.savesCount)
    && sameValue(a.following, b.following);
}

export function derivePostInteractionState(post: any, currentUserId?: string | null): PostInteractionState {
  const userId = post?.user_id ? String(post.user_id) : undefined;
  let liked = boolFromPost(post, ['liked_by_me', 'liked', 'is_liked']);
  if (liked === undefined && Array.isArray(post?.liked_by) && currentUserId) {
    liked = post.liked_by.map(String).includes(String(currentUserId));
  }

  return {
    userId,
    liked,
    likesCount: numberOrUndefined(post?.likes_count ?? post?.likes),
    saved: boolFromPost(post, ['saved', 'is_saved', 'bookmarked', 'is_bookmarked']),
    savesCount: numberOrUndefined(post?.saves_count ?? post?.saved_count ?? post?.saves),
    following: userId && userId !== String(currentUserId || '')
      ? boolFromPost(post, ['is_following', 'followed', 'following'])
      : false,
  };
}

export const useSocialState = create<SocialState>((set) => ({
  posts: {},
  followedUserIds: {},

  hydratePosts: (rawPosts, currentUserId) => set((state) => {
    let posts = state.posts;
    let followedUserIds = state.followedUserIds;
    let changed = false;

    rawPosts.forEach((post) => {
      const postId = String(post?.id || post?.post_id || '');
      if (!postId) return;
      const seed = derivePostInteractionState(post, currentUserId);
      const previous = posts[postId] || {};

      const nextPostState = {
        ...previous,
        userId: seed.userId || previous.userId,
        liked: seed.liked !== undefined ? seed.liked : previous.liked,
        likesCount: seed.likesCount !== undefined ? seed.likesCount : previous.likesCount,
        saved: seed.saved !== undefined ? seed.saved : previous.saved,
        savesCount: seed.savesCount !== undefined ? seed.savesCount : previous.savesCount,
        following: seed.following !== undefined ? seed.following : previous.following,
      };

      if (!samePostState(previous, nextPostState)) {
        if (posts === state.posts) posts = { ...state.posts };
        posts[postId] = nextPostState;
        changed = true;
      }

      if (seed.userId && seed.following !== undefined) {
        if (followedUserIds[seed.userId] !== seed.following) {
          if (followedUserIds === state.followedUserIds) followedUserIds = { ...state.followedUserIds };
          followedUserIds[seed.userId] = seed.following;
          changed = true;
        }
      }
    });

    return changed ? { posts, followedUserIds } : state;
  }),

  setPostLiked: (postId, liked, likesCount) => set((state) => {
    const id = String(postId);
    const previous = state.posts[id] || {};
    const next = {
      ...previous,
      liked,
      ...(likesCount !== undefined ? { likesCount: Math.max(0, likesCount) } : {}),
    };
    return samePostState(previous, next) ? state : { posts: { ...state.posts, [id]: next } };
  }),

  setPostSaved: (postId, saved, savesCount) => set((state) => {
    const id = String(postId);
    const previous = state.posts[id] || {};
    const next = {
      ...previous,
      saved,
      ...(savesCount !== undefined ? { savesCount: Math.max(0, savesCount) } : {}),
    };
    return samePostState(previous, next) ? state : { posts: { ...state.posts, [id]: next } };
  }),

  setUserFollowing: (userId, following) => set((state) => {
    if (state.followedUserIds[String(userId)] === following) return state;
    const nextFollowed = { ...state.followedUserIds, [String(userId)]: following };
    const posts = Object.fromEntries(Object.entries(state.posts).map(([postId, postState]) => (
      postState.userId === String(userId)
        ? [postId, { ...postState, following }]
        : [postId, postState]
    )));
    return { followedUserIds: nextFollowed, posts };
  }),
}));
