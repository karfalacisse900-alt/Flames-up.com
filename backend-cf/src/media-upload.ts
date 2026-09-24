export function cloudflareTusCreationHeaders(input: {
  token: string;
  fileSize: number;
  maxDurationSeconds: number;
  requireSignedURLs: boolean;
  creatorId: string;
  filename: string;
}): Record<string, string> {
  const metadata = [
    ['maxDurationSeconds', String(input.maxDurationSeconds)],
    ...(input.requireSignedURLs ? [['requiresignedurls', 'true']] : []),
    ['name', input.filename],
  ].map(([key, value]) => {
    const utf8 = new TextEncoder().encode(value);
    const encoded = btoa(Array.from(utf8, (byte) => String.fromCharCode(byte)).join(''));
    return `${key} ${encoded}`;
  }).join(',');
  return {
    Authorization: `Bearer ${input.token}`,
    'Tus-Resumable': '1.0.0',
    'Upload-Length': String(input.fileSize),
    'Upload-Metadata': metadata,
    'Upload-Creator': input.creatorId,
  };
}
