// Compatibility wake-up endpoint. Delivery happens only through the durable outbox.
Deno.serve(async (request) => {
  const expected = Deno.env.get('NOTIFY_SALE_SECRET');
  if (request.method !== 'POST' || !expected || request.headers.get('x-notify-sale-secret') !== expected) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const secret = Deno.env.get('SALE_OUTBOX_DISPATCH_SECRET');
  const url = Deno.env.get('SUPABASE_URL');
  if (!secret || !url) return Response.json({ error: 'Missing dispatcher configuration' }, { status: 503 });
  try {
    const payload = await request.json().catch(() => ({}));
    const id = payload.record?.id;
    if (Number.isSafeInteger(id) && id > 0) {
      // An old pg_net request can arrive after migration. Re-read the row and
      // deduplicate the enqueue rather than trusting the webhook's sale contents.
      const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
      const queued = await fetch(`${url}/rest/v1/rpc/enqueue_legacy_sale_notification`, {
        method: 'POST', signal: AbortSignal.timeout(15000),
        headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
        body: JSON.stringify({ sale_id: id }),
      });
      if (!queued.ok) throw new Error('Legacy enqueue failed');
    }
    const response = await fetch(`${url}/functions/v1/dispatch-sale-notifications`, {
      method: 'POST', signal: AbortSignal.timeout(45000),
      headers: { 'Content-Type': 'application/json', 'x-sale-dispatch-secret': secret,
        'apikey': Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_ANON_KEY') ?? ''}` },
      body: '{}',
    });
    return Response.json({ ok: response.ok }, { status: response.ok ? 200 : 502 });
  } catch (_) {
    return Response.json({ error: 'Dispatcher unavailable; scheduled retry remains active' }, { status: 503 });
  }
});
