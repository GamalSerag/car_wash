import { buildMessage, sendPush } from '../_shared/firebase.ts';
import { handleDispatch } from './index.ts';

function assert(value: unknown, message = 'Assertion failed'): asserts value {
  if (!value) throw new Error(message);
}

Deno.test('Arabic FCM payload stays below byte limit and tags are event-specific', () => {
  const event = { id: 'event-1', title: 'ملخص المزامنة', body: 'عملية غسيل بدون إنترنت '.repeat(500),
    data: { type: 'offline_sale_summary', batch_id: 'batch', company_id: 'company' } };
  const result = buildMessage(event, 'device');
  assert(new TextEncoder().encode(JSON.stringify(result)).length <= 3800);
  assert(result.message.android.notification.tag === 'event-1');
  assert(buildMessage({ ...event, id: 'event-2' }, 'device').message.android.notification.tag !== result.message.android.notification.tag);
  assert(result.message.data.batch_id === 'batch');
});

Deno.test('Dispatcher refuses requests without server-only credentials', async () => {
  Deno.env.set('SALE_OUTBOX_DISPATCH_SECRET', 'test-secret');
  const response = await handleDispatch(new Request('http://localhost', { method: 'POST' }));
  assert(response.status === 401);
});

Deno.test('Dispatcher claims outbox with a worker identity and handles an empty queue', async () => {
  Deno.env.set('SALE_OUTBOX_DISPATCH_SECRET', 'test-secret');
  Deno.env.set('SUPABASE_URL', 'https://test.example.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-only-not-a-real-key');
  const original = globalThis.fetch;
  let claims = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    assert(url.endsWith('/rpc/claim_sale_notification_events'));
    const params = JSON.parse(init?.body as string);
    assert(typeof params.worker === 'string'); claims++;
    return Response.json([]);
  }) as typeof fetch;
  try {
    const response = await handleDispatch(new Request('http://localhost', { method: 'POST', headers: { 'x-sale-dispatch-secret': 'test-secret' } }));
    assert(response.status === 200 && claims === 1);
  } finally { globalThis.fetch = original; }
});

Deno.test('Firebase sends only through OAuth, retries one 401 and detects UNREGISTERED', async () => {
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const raw = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let bytes = ''; for (const b of raw) bytes += String.fromCharCode(b);
  Deno.env.set('FIREBASE_SERVICE_ACCOUNT_JSON', JSON.stringify({ client_email: 'test@example.invalid', project_id: 'fake-project',
    private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(bytes)}\n-----END PRIVATE KEY-----` }));
  const original = globalThis.fetch;
  let oauth = 0; let sends = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.includes('oauth2.googleapis.com')) { oauth++; return Response.json({ access_token: 'fake-access-token' }); }
    assert((init?.headers as Record<string, string>).Authorization === 'Bearer fake-access-token');
    sends++;
    if (sends === 1) return Response.json({ error: { status: 'UNAUTHENTICATED' } }, { status: 401 });
    return Response.json({ error: { details: [{ errorCode: 'UNREGISTERED' }] } }, { status: 404 });
  }) as typeof fetch;
  try {
    const result = await sendPush({ id: 'id', title: 'اختبار', body: 'اختبار', data: {} }, 'fake-device');
    assert(result.invalid === true && sends === 2 && oauth === 2);
  } finally { globalThis.fetch = original; Deno.env.delete('FIREBASE_SERVICE_ACCOUNT_JSON'); }
});

Deno.test('Per-device retries do not resend a successfully delivered event', async () => {
  Deno.env.set('SALE_OUTBOX_DISPATCH_SECRET', 'test-secret');
  Deno.env.set('SUPABASE_URL', 'https://test.example.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-only-not-a-real-key');
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const raw = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let encoded = ''; for (const byte of raw) encoded += String.fromCharCode(byte);
  Deno.env.set('FIREBASE_SERVICE_ACCOUNT_JSON', JSON.stringify({ client_email: 'test@example.invalid', project_id: 'fake-project',
    private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(encoded)}\n-----END PRIVATE KEY-----` }));
  const deliveries = [{ token: 'device-a', recipient_id: 'admin-a', state: 'pending', attempts: 0 },
    { token: 'device-b', recipient_id: 'admin-b', state: 'pending', attempts: 0 }];
  const sends: Record<string, number> = {}; const finishes: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input instanceof Request ? input.url : input));
    if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 'fake-access-token' });
    if (url.hostname === 'fcm.googleapis.com') {
      const device = JSON.parse(init?.body as string).message.token;
      sends[device] = (sends[device] ?? 0) + 1;
      if (device === 'device-b' && sends[device] === 1) return Response.json({ error: { status: 'UNAVAILABLE' } }, { status: 503 });
      return Response.json({ name: `projects/fake-project/messages/${device}` });
    }
    const args = init?.body ? JSON.parse(init.body as string) : {};
    if (url.pathname.endsWith('/rpc/claim_sale_notification_events')) return Response.json([{
      id: 'event', company_id: 'company', employee_id: 'employee', attempts: finishes.length + 1,
      title: 'ملخص', body: 'عمليات بدون إنترنت', data: { type: 'offline_sale_summary', batch_id: 'batch' },
    }]);
    if (url.pathname.endsWith('/companies')) return Response.json({ is_active: true });
    if (url.pathname.endsWith('/rpc/prepare_sale_notification_deliveries')) return Response.json(deliveries.filter(d => d.state !== 'sent'));
    if (url.pathname.endsWith('/profiles')) return Response.json({ role: 'admin', is_active: true, company_id: 'company' });
    if (url.pathname.endsWith('/device_tokens')) return Response.json({ user_id: url.searchParams.get('token')?.endsWith('device-a') ? 'admin-a' : 'admin-b', company_id: 'company' });
    if (url.pathname.endsWith('/rpc/record_sale_notification_delivery')) {
      const delivery = deliveries.find(d => d.token === args.device_token)!;
      assert(delivery.state !== 'sent', 'A successful delivery was retried');
      delivery.state = args.delivery_state; delivery.attempts++;
      return Response.json(null);
    }
    if (url.pathname.endsWith('/sale_notification_deliveries')) return Response.json(deliveries);
    if (url.pathname.endsWith('/rpc/finish_sale_notification_event')) { finishes.push(args.desired_state); return Response.json(null); }
    throw new Error(`Unexpected mocked request ${url.pathname}`);
  }) as typeof fetch;
  const request = () => new Request('http://localhost', { method: 'POST', headers: { 'x-sale-dispatch-secret': 'test-secret' } });
  try {
    assert((await handleDispatch(request())).status === 200);
    assert((await handleDispatch(request())).status === 200);
    assert(sends['device-a'] === 1 && sends['device-b'] === 2);
    assert(finishes.join(',') === 'pending,sent');
  } finally { globalThis.fetch = original; Deno.env.delete('FIREBASE_SERVICE_ACCOUNT_JSON'); }
});

Deno.test('Inactive companies never reach Firebase delivery', async () => {
  Deno.env.set('SALE_OUTBOX_DISPATCH_SECRET', 'test-secret');
  Deno.env.set('SUPABASE_URL', 'https://test.example.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-only-not-a-real-key');
  const original = globalThis.fetch; let skipped = false;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes('/rpc/claim_sale_notification_events')) return Response.json([{ id: 'event', company_id: 'company', attempts: 1 }]);
    if (url.includes('/companies')) return Response.json({ is_active: false });
    if (url.includes('/rpc/finish_sale_notification_event')) {
      skipped = JSON.parse(init?.body as string).desired_state === 'skipped'; return Response.json(null);
    }
    throw new Error('Inactive company attempted a delivery');
  }) as typeof fetch;
  try {
    const response = await handleDispatch(new Request('http://localhost', { method: 'POST', headers: { 'x-sale-dispatch-secret': 'test-secret' } }));
    assert(response.status === 200 && skipped);
  } finally { globalThis.fetch = original; }
});

Deno.test('Token permission failure is reported without marking a delivery sent', async () => {
  Deno.env.set('SALE_OUTBOX_DISPATCH_SECRET', 'test-secret');
  Deno.env.set('SUPABASE_URL', 'https://test.example.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-only-not-a-real-key');
  const original = globalThis.fetch;
  let failure: string | undefined;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input instanceof Request ? input.url : input));
    if (url.pathname.endsWith('/rpc/claim_sale_notification_events')) {
      return Response.json([{ id: 'event', company_id: 'company', attempts: 1 }]);
    }
    if (url.pathname.endsWith('/companies')) return Response.json({ is_active: true });
    if (url.pathname.endsWith('/rpc/prepare_sale_notification_deliveries')) {
      return Response.json([{ token: 'private-device-token', recipient_id: 'admin' }]);
    }
    if (url.pathname.endsWith('/profiles')) {
      return Response.json({ role: 'admin', is_active: true, company_id: 'company' });
    }
    if (url.pathname.endsWith('/device_tokens')) {
      return Response.json({ code: '42501', message: 'permission denied for table device_tokens' }, { status: 403 });
    }
    if (url.pathname.endsWith('/rpc/finish_sale_notification_event')) {
      const args = JSON.parse(init?.body as string);
      assert(args.desired_state === 'pending');
      failure = args.failure;
      return Response.json(null);
    }
    throw new Error('Permission failure must not send or acknowledge a delivery');
  }) as typeof fetch;
  try {
    const response = await handleDispatch(new Request('http://localhost', {
      method: 'POST', headers: { 'x-sale-dispatch-secret': 'test-secret' },
    }));
    assert(response.status === 200);
    assert(failure === 'Recipient lookup failed: device_tokens 42501');
    assert(!failure.includes('private-device-token'));
  } finally { globalThis.fetch = original; }
});
