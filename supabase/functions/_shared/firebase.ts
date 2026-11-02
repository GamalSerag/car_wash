type ServiceAccount = { client_email: string; private_key: string; project_id: string };
let cached: { token: string; expires: number } | undefined;

function b64(bytes: Uint8Array): string {
  let value = '';
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function encoded(value: unknown): string {
  return b64(new TextEncoder().encode(JSON.stringify(value)));
}

function account(): ServiceAccount {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!raw) throw new Error('Missing Firebase backend credentials');
  const value = JSON.parse(raw) as ServiceAccount;
  if (!value.project_id || !value.client_email || !value.private_key) throw new Error('Invalid Firebase backend credentials');
  return value;
}

async function token(service: ServiceAccount, force = false): Promise<string> {
  if (!force && cached && cached.expires > Date.now()) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encoded({ alg: 'RS256', typ: 'JWT' })}.${encoded({
    iss: service.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  })}`;
  const body = service.private_key.replaceAll('\\n', '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
  const raw = Uint8Array.from(atob(body), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', raw,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(15000),
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64(new Uint8Array(signature))}` }),
  });
  if (!response.ok) throw new Error(`Firebase OAuth ${response.status}`);
  const result = await response.json();
  if (typeof result.access_token !== 'string') throw new Error('Missing Firebase OAuth token');
  cached = { token: result.access_token, expires: Date.now() + 3000000 };
  return cached.token;
}

export type PushEvent = { id: string; title: string; body: string; data: Record<string, unknown> };

export function buildMessage(event: PushEvent, device: string) {
  const data: Record<string, string> = { event_id: event.id };
  for (const [key, value] of Object.entries(event.data)) data[key] = String(value);
  const message = { token: device, notification: { title: event.title.slice(0, 120), body: event.body },
    data, android: { priority: 'HIGH', notification: { tag: event.id, sound: 'default' } } };
  while (new TextEncoder().encode(JSON.stringify({ message })).length > 3800 && message.notification.body.length > 20) {
    message.notification.body = message.notification.body.slice(0, -20);
  }
  if (new TextEncoder().encode(JSON.stringify({ message })).length > 3800) throw new Error('FCM payload too large');
  return { message };
}

export async function sendPush(event: PushEvent, device: string): Promise<{ name?: string; invalid?: boolean; retryAfter?: number }> {
  const service = account();
  const send = async (force: boolean) => fetch(`https://fcm.googleapis.com/v1/projects/${service.project_id}/messages:send`, {
    method: 'POST', signal: AbortSignal.timeout(15000),
    headers: { Authorization: `Bearer ${await token(service, force)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(buildMessage(event, device)),
  });
  let response = await send(false);
  if (response.status === 401) response = await send(true);
  const body = await response.json();
  const invalid = body.error?.details?.some((detail: { errorCode?: string }) => detail.errorCode === 'UNREGISTERED');
  if (invalid) return { invalid: true };
  if (!response.ok) {
    const error = new Error(`FCM ${response.status}: ${body.error?.status ?? 'send_failed'}`) as Error & { retryAfter?: number };
    const retry = Number(response.headers.get('retry-after'));
    if (Number.isFinite(retry) && retry > 0) error.retryAfter = retry;
    throw error;
  }
  if (typeof body.name !== 'string') throw new Error('FCM response missing message name');
  return { name: body.name };
}
