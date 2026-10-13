const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-notify-signup-request-secret',
};

type SignupRequestRecord = {
  id?: number;
  company_name?: string | null;
  owner_name?: string | null;
  phone?: string | null;
  email?: string | null;
};

type WebhookPayload = {
  record?: SignupRequestRecord;
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

  const expectedSecret = Deno.env.get('NOTIFY_SIGNUP_REQUEST_SECRET');
  const requestSecret = request.headers.get('x-notify-signup-request-secret');

  if (!expectedSecret || requestSecret !== expectedSecret) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  try {
    const payload = (await request.json()) as WebhookPayload;
    const signupRequest = payload.record;

    if (!signupRequest) {
      return jsonResponse({ error: 'Missing signup request record' }, 400);
    }

    const serviceAccount = getFirebaseServiceAccount();
    const accessToken = await getFirebaseAccessToken(serviceAccount);
    const response = await sendSuperAdminNotification(
      serviceAccount.project_id,
      accessToken,
      signupRequest,
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

async function sendSuperAdminNotification(
  projectId: string,
  accessToken: string,
  signupRequest: SignupRequestRecord,
) {
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
          topic: 'super_admins',
          notification: {
            title: 'طلب اشتراك جديد',
            body: buildNotificationBody(signupRequest),
          },
          android: {
            priority: 'HIGH',
            notification: {
              sound: 'default',
            },
          },
          data: {
            type: 'signup_request_inserted',
            request_id: String(signupRequest.id ?? ''),
            company_name: signupRequest.company_name ?? '',
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

function buildNotificationBody(signupRequest: SignupRequestRecord): string {
  const companyName = signupRequest.company_name?.trim() || 'شركة جديدة';
  const ownerName = signupRequest.owner_name?.trim();
  const phone = signupRequest.phone?.trim();

  if (ownerName && phone) {
    return `${companyName} - ${ownerName} - ${phone}`;
  }

  if (ownerName) {
    return `${companyName} - ${ownerName}`;
  }

  return companyName;
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
