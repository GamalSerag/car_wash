import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.118.0';
import { sendPush, type PushEvent } from '../_shared/firebase.ts';

export async function handleDispatch(request: Request): Promise<Response> {
  const secret = Deno.env.get('SALE_OUTBOX_DISPATCH_SECRET');
  if (request.method !== 'POST' || !secret || request.headers.get('x-sale-dispatch-secret') !== secret) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const backend = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const worker = crypto.randomUUID();
  const started = Date.now();
  async function rpc(name: string, params: Record<string, unknown>) {
    const { data, error } = await backend.rpc(name, params);
    if (error) throw new Error(`${name}: ${error.code}`);
    return data;
  }
  let processed = 0;
  try {
    const events = await rpc('claim_sale_notification_events', { worker, limit_count: 5 });
    for (const event of events) {
      if (Date.now() - started > 40000) break;
      let desired = 'pending';
      let failure: string | null = null;
      let retryAfter = Math.min(1800, 30 * 2 ** (event.attempts - 1));
      try {
        const { data: company, error: companyError } = await backend.from('companies').select('is_active').eq('id', event.company_id).single();
        if (companyError) throw new Error('Company lookup failed');
        if (!company.is_active) desired = 'skipped';
        else {
          const targets = await rpc('prepare_sale_notification_deliveries', { event_id: event.id, worker });
          for (const delivery of targets) {
            if (Date.now() - started > 40000) break;
            // Recheck both membership and token ownership; topic subscription is not authorization.
            const { data: profile, error: profileError } = await backend.from('profiles').select('role,is_active,company_id')
              .eq('id', delivery.recipient_id).maybeSingle();
            const { data: currentToken, error: tokenError } = await backend.from('device_tokens').select('user_id,company_id')
              .eq('token', delivery.token).maybeSingle();
            if (profileError || tokenError) {
              const source = profileError ? 'profiles' : 'device_tokens';
              throw new Error(`Recipient lookup failed: ${source} ${(profileError ?? tokenError)!.code}`);
            }
            let state = 'invalid'; let provider: string | null = null; let deliveryError: string | null = null;
            if (profile?.is_active && profile.role === 'admin' && profile.company_id === event.company_id &&
                currentToken?.user_id === delivery.recipient_id && currentToken?.company_id === event.company_id) {
              try {
                const response = await sendPush(event as PushEvent, delivery.token);
                state = response.invalid ? 'invalid' : 'sent'; provider = response.name ?? null;
                if (response.invalid) await backend.from('device_tokens').delete().eq('token', delivery.token).eq('user_id', delivery.recipient_id);
              } catch (error) {
                state = 'failed'; deliveryError = error instanceof Error ? error.message : 'FCM request failed';
                retryAfter = Math.max(retryAfter, (error as { retryAfter?: number }).retryAfter ?? 0);
              }
            }
            await rpc('record_sale_notification_delivery', { event_id: event.id, worker,
              device_token: delivery.token, delivery_state: state, provider_name: provider, failure: deliveryError });
          }
          const { data: deliveries, error } = await backend.from('sale_notification_deliveries').select('state,attempts').eq('event_id', event.id);
          if (error) throw new Error('Delivery lookup failed');
          if (deliveries?.length && deliveries.every(d => ['sent', 'invalid'].includes(d.state))) {
            desired = deliveries.some(d => d.state === 'sent') ? 'sent' : 'skipped';
          }
          else failure = 'Waiting for recipients or retrying failed deliveries';
        }
      } catch (error) { failure = error instanceof Error ? error.message : 'Dispatch failed'; }
      await rpc('finish_sale_notification_event', { event_id: event.id, worker, desired_state: desired, failure, retry_after: retryAfter });
      processed++;
    }
    return Response.json({ ok: true, processed });
  } catch (error) {
    console.error('Sale dispatcher failed', error instanceof Error ? error.message : 'unknown');
    return Response.json({ error: 'Dispatch failed' }, { status: 500 });
  }
}

if (import.meta.main) Deno.serve(handleDispatch);
