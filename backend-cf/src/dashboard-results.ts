/** Failed independent queries are unavailable, never a successful zero count. */
export async function dashboardResults(queries: Record<string, () => Promise<unknown>>) {
  const values: Record<string, any> = {};
  const errors: Record<string, string> = {};
  await Promise.all(Object.entries(queries).map(async ([key, query]) => {
    try { values[key] = await query(); }
    catch { values[key] = null; errors[key] = 'Temporarily unavailable. Refresh to retry.'; }
  }));
  return { values, errors };
}
