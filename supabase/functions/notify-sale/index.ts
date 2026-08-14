const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-notify-sale-secret',
};

type SaleRecord = {
  id?: number;
  price?: number | string;
  vehicle_name?: string | null;
  plate_number?: string | null;
  created_at?: string;
};

type WebhookPayload = {
  record?: SaleRecord;
};

type FirebaseServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const expectedSecret = Deno.env.get('NOTIFY_SALE_SECRET');
  const requestSecret = request.headers.get('x-notify-sale-secret');

  if (!expectedSecret || requestSecret !== expectedSecret) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  try {
    const payload = (await request.json()) as WebhookPayload;
    const sale = payload.record;

    if (!sale) {
      return jsonResponse({ error: 'Missing sale record' }, 400);
    }

    const serviceAccount = getFirebaseServiceAccount();
    const accessToken = await getFirebaseAccessToken(serviceAccount);
    const response = await sendAdminNotification(
      serviceAccount.project_id,
      accessToken,
      sale,
    );

    return jsonResponse({ ok: true, firebase: response }, 200);
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: 'Failed to send notification' }, 500);
  }
});

function getFirebaseServiceAccount(): FirebaseServiceAccount {
  const rawServiceAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

  if (!rawServiceAccount) {
    throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_JSON');
  }

  const serviceAccount = JSON.parse(rawServiceAccount) as FirebaseServiceAccount;

  if (
    !serviceAccount.client_email ||
    !serviceAccount.private_key ||
    !serviceAccount.project_id
  ) {
    throw new Error('Invalid Firebase service account');
  }

  return serviceAccount;
}

async function getFirebaseAccessToken(
  serviceAccount: FirebaseServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const unsignedJwt = `${base64UrlEncodeJson(header)}.${base64UrlEncodeJson(
    claimSet,
  )}`;
  const signature = await signJwt(unsignedJwt, serviceAccount.private_key);
  const jwt = `${unsignedJwt}.${signature}`;

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(await tokenResponse.text());
  }

  const tokenJson = await tokenResponse.json() as { access_token?: string };

  if (!tokenJson.access_token) {
    throw new Error('Firebase access token was not returned');
  }

  return tokenJson.access_token;
}

async function sendAdminNotification(
  projectId: string,
  accessToken: string,
  sale: SaleRecord,
) {
  const title = 'عملية غسيل جديدة';
  const body = buildNotificationBody(sale);

  const fcmResponse = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          topic: 'admins',
          notification: {
            title,
            body,
          },
          android: {
            priority: 'HIGH',
            notification: {
              sound: 'default',
            },
          },
          data: {
            type: 'sale_inserted',
            sale_id: String(sale.id ?? ''),
          },
        },
      }),
    },
  );

  if (!fcmResponse.ok) {
    throw new Error(await fcmResponse.text());
  }

  return await fcmResponse.json();
}

function buildNotificationBody(sale: SaleRecord): string {
  const price = sale.price == null ? '' : ` - ${sale.price} جنيه`;
  const vehicle = sale.vehicle_name || sale.plate_number || 'تمت إضافة مركبة';
  return `${vehicle}${price}`;
}

async function signJwt(unsignedJwt: string, privateKey: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedJwt),
  );

  return base64UrlEncodeBytes(new Uint8Array(signature));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll('\\n', '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes.buffer;
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = '';

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
