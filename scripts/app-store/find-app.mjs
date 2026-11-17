// A read-only fallback for Apple's failing bundle-filter endpoint. Every result
// is still matched against the exact bundle ID; never select the first app.
export async function findApp(get, bundleID) {
  let result;
  try {
    result = await get('apps?' + new URLSearchParams({'filter[bundleId]':bundleID,limit:'1'}));
  } catch (error) {
    if (![500,502,503,504].includes(error.status)) throw error;
    result = await get('apps?' + new URLSearchParams({limit:'200','fields[apps]':'bundleId'}));
  }
  const matches = (result.data ?? []).filter(app => app.attributes?.bundleId === bundleID);
  if (matches.length !== 1) throw Error('Expected one app matching the exact bundle ID');
  return matches[0];
}
