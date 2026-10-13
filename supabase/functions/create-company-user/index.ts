import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type UserInput = {
  full_name?: string;
  email?: string;
  password?: string;
};

type RequestBody = {
  request_id?: number;
  company_name?: string;
  admin?: UserInput;
  employee?: UserInput;
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const anonKey = requiredEnv('SUPABASE_ANON_KEY');
    const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
    const authorization = request.headers.get('Authorization');

    if (!authorization) {
      return jsonResponse({ error: 'Missing authorization header' }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const { data: profile, error: profileError } = await serviceClient
      .from('profiles')
      .select('role, is_active')
      .eq('id', authData.user.id)
      .single();

    if (
      profileError ||
      !profile ||
      profile.role !== 'super_admin' ||
      profile.is_active !== true
    ) {
      return jsonResponse({ error: 'Super admin only' }, 403);
    }

    const body = (await request.json()) as RequestBody;
    const companyName = clean(body.company_name);
    const admin = body.admin;

    if (!companyName || !isValidUser(admin)) {
      return jsonResponse({ error: 'Missing company or admin data' }, 400);
    }

    const { data: company, error: companyError } = await serviceClient
      .from('companies')
      .insert({ name: companyName })
      .select('id, name')
      .single();

    if (companyError || !company) {
      throw companyError ?? new Error('Company was not created');
    }

    const adminUser = await createAuthUser(serviceClient, admin, company.id);
    await upsertProfile(serviceClient, {
      id: adminUser.id,
      companyId: company.id,
      fullName: clean(admin.full_name) ?? admin.email!,
      role: 'admin',
    });

    let employeeUser = null;
    if (isValidUser(body.employee)) {
      employeeUser = await createAuthUser(
        serviceClient,
        body.employee,
        company.id,
      );
      await upsertProfile(serviceClient, {
        id: employeeUser.id,
        companyId: company.id,
        fullName: clean(body.employee.full_name) ?? body.employee.email!,
        role: 'employee',
      });
    }

    if (body.request_id != null) {
      await serviceClient
        .from('signup_requests')
        .update({
          status: 'approved',
          company_id: company.id,
          approved_by: authData.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', body.request_id);
    }

    return jsonResponse(
      {
        ok: true,
        company,
        admin_user_id: adminUser.id,
        employee_user_id: employeeUser?.id ?? null,
      },
      200,
    );
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: 'Failed to create company users' }, 500);
  }
});

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

function clean(value?: string): string | null {
  const trimmed = value?.trim() ?? '';
  return trimmed.length === 0 ? null : trimmed;
}

function isValidUser(user?: UserInput): user is Required<UserInput> {
  return Boolean(clean(user?.full_name) && clean(user?.email) && user?.password);
}

async function createAuthUser(
  serviceClient: ReturnType<typeof createClient>,
  user: Required<UserInput>,
  companyId: string,
) {
  const { data, error } = await serviceClient.auth.admin.createUser({
    email: user.email.trim(),
    password: user.password,
    email_confirm: true,
    user_metadata: {
      full_name: user.full_name.trim(),
      company_id: companyId,
    },
  });

  if (error || !data.user) {
    throw error ?? new Error('Auth user was not created');
  }

  return data.user;
}

async function upsertProfile(
  serviceClient: ReturnType<typeof createClient>,
  values: {
    id: string;
    companyId: string;
    fullName: string;
    role: 'admin' | 'employee';
  },
) {
  const { error } = await serviceClient.from('profiles').upsert({
    id: values.id,
    company_id: values.companyId,
    full_name: values.fullName,
    role: values.role,
    is_active: true,
  });

  if (error) {
    throw error;
  }
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
