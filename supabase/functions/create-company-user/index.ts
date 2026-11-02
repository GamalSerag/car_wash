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
      return jsonResponse({ error: 'unauthorized', message: 'انتهت جلسة الدخول. سجل الدخول مرة أخرى' }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: 'unauthorized', message: 'انتهت جلسة الدخول. سجل الدخول مرة أخرى' }, 401);
    }

    const { data: profile, error: profileError } = await serviceClient
      .from('profiles')
      .select('role, is_active')
      .eq('id', authData.user.id)
      .single();

    if (profileError) {
      console.error('Profile authorization lookup failed', { code: profileError.code });
      return jsonResponse({
        error: 'profile_lookup_failed',
        message: 'تعذر قراءة صلاحيات الحساب من قاعدة البيانات. تواصل مع الدعم',
      }, 500);
    }

    if (
      !profile ||
      profile.role !== 'super_admin' ||
      profile.is_active !== true
    ) {
      return jsonResponse({ error: 'forbidden', message: 'إنشاء الشركات متاح للمشرف العام النشط فقط' }, 403);
    }

    const body = (await request.json()) as RequestBody;
    const companyName = clean(body.company_name);
    const admin = body.admin;

    if (!companyName || Array.from(companyName).length > 100 || !isValidUser(admin)) {
      return jsonResponse({ error: 'invalid_input', message: 'أكمل بيانات الشركة والمدير' }, 400);
    }

    if (body.employee != null && !isValidUser(body.employee)) {
      return jsonResponse({ error: 'invalid_input', message: 'أكمل جميع بيانات الموظف أو اتركها فارغة' }, 400);
    }
    if (body.employee && clean(body.employee.email)?.toLowerCase() === clean(admin.email)?.toLowerCase()) {
      return jsonResponse({ error: 'invalid_input', message: 'يجب أن يختلف بريد المدير عن بريد الموظف' }, 400);
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
      const { error: approvalError } = await serviceClient
        .from('signup_requests')
        .update({
          status: 'approved',
          company_id: company.id,
          approved_by: authData.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', body.request_id);
      if (approvalError) {
        console.error('Signup request approval failed', { code: approvalError.code });
        return jsonResponse({
          error: 'approval_failed',
          message: 'تم إنشاء الشركة والحسابات، لكن تعذر تحديث طلب الاشتراك. حدث البيانات ولا تكرر إنشاء الحسابات',
        }, 500);
      }
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
    const code = typeof error === 'object' && error !== null && 'code' in error
      ? String(error.code)
      : 'creation_failed';
    console.error('Company creation failed', { code });
    const messages: Record<string, string> = {
      email_exists: 'البريد الإلكتروني مسجل بالفعل. استخدم بريدا آخر',
      user_already_exists: 'يوجد حساب مسجل بهذا البريد الإلكتروني',
      email_address_invalid: 'البريد الإلكتروني غير صالح',
      weak_password: 'كلمة المرور لا تحقق شروط الأمان المطلوبة',
      validation_failed: 'راجع البريد الإلكتروني وكلمة المرور',
      over_request_rate_limit: 'طلبات كثيرة. انتظر قليلا ثم حاول مرة أخرى',
      unexpected_failure: 'تعذر إنشاء الحساب في قاعدة البيانات. راجع سجل Auth والمشغل الخاص بإنشاء الملف الشخصي',
    };
    const message = messages[code] ?? 'تعذر إنشاء الشركة أو الحسابات. راجع سجل الدالة في Supabase';
    return jsonResponse({ error: code, message }, code in messages && code !== 'unexpected_failure' ? 400 : 500);
  }
});

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

function clean(value?: unknown): string | null {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  return trimmed.length === 0 ? null : trimmed;
}

function isValidUser(user?: UserInput): user is Required<UserInput> {
  const name = clean(user?.full_name);
  const email = clean(user?.email);
  return Boolean(name && Array.from(name).length <= 100 &&
    email && Array.from(email).length <= 254 &&
    typeof user?.password === 'string' && user.password.length > 0 &&
    Array.from(user.password).length <= 128);
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
