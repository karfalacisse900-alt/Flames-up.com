const headers = { Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}` };
async function read(path) {
  const response = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    headers, signal: AbortSignal.timeout(20_000),
  });
  const data = await response.json();
  if (!response.ok || !data.success) {
    console.log(JSON.stringify({ path, status: response.status, errorCodes: data.errors?.map(error => error.code) }));
    return null;
  }
  return data.result;
}

for (const name of ['flames-up.com', 'api.flames-up.com']) {
  const zones = await read(`/zones?name=${name}`);
  for (const zone of zones || []) {
    console.log(JSON.stringify({ zone: zone.name, status: zone.status }));
    const security = await read(`/zones/${zone.id}/settings/security_level`);
    if (security) console.log(JSON.stringify({ zone: zone.name, securityLevel: security.value }));
    const custom = await read(`/zones/${zone.id}/rulesets/phases/http_request_firewall_custom/entrypoint`);
    if (custom) console.log(JSON.stringify({ zone: zone.name, rules: custom.rules?.map(rule => ({
      id: rule.id, action: rule.action, enabled: rule.enabled, description: rule.description,
      expression: String(rule.expression).replace(/[A-Za-z0-9+/_=-]{40,}/g, '[redacted]'),
    })) }));
  }
}
