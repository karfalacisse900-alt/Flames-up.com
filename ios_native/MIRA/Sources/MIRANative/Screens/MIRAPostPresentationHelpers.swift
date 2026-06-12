import Foundation

func miraShouldOpenSinglePhotoPreview(_ post: MIRAPost) -> Bool {
  guard !post.containsVideoMedia else { return false }
  let mediaCount = max(post.feedMediaURLs.count, post.mediaURLs.count)
  return mediaCount <= 1
}
