# Offline Wash Sales Sync — خطة التنفيذ

التاريخ: 2026-11-01، Africa/Cairo.

تحديث سياسة الإشعارات بتاريخ 2026-11-02 بطلب المستخدم: الحد الحالي **5 طلبات بدلًا من 10**. من 1 إلى 5: إشعار فردي لكل طلب مقبول + ملخص دائم. من 6 فأكثر: ملخص واحد فقط. أرقام 10 في المواصفات الأصلية أدناه توثق السياسة السابقة؛ اختبارات الخادم الحالية تغطي الحدود 5/6، وتنسيق المبالغ بدون أصفار زائدة والتوقيت المختصر بتوقيت القاهرة مع عزل اتجاه الأرقام داخل العربية.

الحالة المحدثة بتاريخ 2026-11-02: **تم تنفيذ الكود ونشر الخادم بعد موافقة المستخدم**. الأقسام التالية تحفظ مواصفات الخطة الأصلية، وسجل التحقق في نهاية الملف يوضح ما نُفذ فعلًا. اختبار الهاتف الحقيقي وظهور push على جهاز المدير لم يُنفذا لعدم وجود جهاز متصل؛ لا تعلّم هذه المرحلة مكتملة دون دليل.

## 1. المعمارية الحالية والقرارات

### ما تم فحصه

| المسار | الوضع الحالي | الأثر على التنفيذ |
| --- | --- | --- |
| `pubspec.yaml` / `pubspec.lock` | الإصدار `1.0.9+11`؛ `supabase_flutter` المقفل 2.18.3، Firebase Messaging 16.7.0، Firebase Core 4.15.0 | لا ترقيات عامة للحزم |
| `lib/main.dart` | تهيئة Firebase ثم Supabase، Material 3، العربية وRTL | تهيئة التخزين ومراقب المزامنة دون تعطيل بدء التطبيق |
| `lib/screens/auth_gate.dart` | تحميل الملف الشخصي من الشبكة؛ خطأ التحميل الأول يؤدي لشاشة الدخول؛ مراقبة الشركة Realtime وفحص كل 30 ثانية | يلزم استرجاع محدود وآمن لملف الموظف المحفوظ |
| `lib/services/auth_service.dart` | `getCurrentProfile()` يقرأ `profiles` مع `companies(name, is_active)` | الاحتفاظ بآخر قرار صلاحيات مؤكد، وعدم تفسير انقطاع الشبكة كخروج |
| `lib/widgets/app_update_gate.dart` | التحقق الأول من الإصدار إلزامي، وفشله يحجب التطبيق | تخزين سياسة التحديث الناجحة؛ لا يلغي الأوفلاين حظر تحديث معروف |
| `lib/services/app_update_service.dart` | يرجع سياسة فقط إذا كان البناء قديمًا | يلزم تخزين السياسة الخام حتى عند عدم الحاجة للتحديث |
| `lib/screens/home_screen.dart` | StatefulWidget، `Future.wait` للملف الشخصي ومبيعات اليوم، إجمالي من القائمة؛ أدوات مشتركة يستخدمها المدير | استخدام مستودع مبيعات موظف محلي/بعيد مع الحفاظ على الأدوات المشتركة |
| `lib/screens/add_sale_screen.dart` | أنواع المركبات من الشبكة؛ `createSale()` / `updateSale()`؛ الأخطاء عامة | حفظ محلي دائم أولًا، وتمييز رسالة الحفظ المحلي عن تأكيد السيرفر |
| `lib/services/sales_service.dart` | INSERT مباشر؛ `getTodaySales()` من الشبكة؛ تغليف الاستثناءات | فصل أخطاء الشبكة/الصلاحيات، وإضافة مسار idempotent بدل INSERT قابل للتكرار |
| `lib/models/sale_model.dart` | `id` من نوع `int`؛ companyId وعلاقات النوع والموظف | لا تحول معرّف الإنتاج إلى UUID |
| `lib/services/vehicle_type_service.dart` | الأنواع النشطة من Supabase مباشرة | تخزين مرجعي محلي مفصول بالشركة والموظف |
| `lib/screens/admin_home_screen.dart` | اشتراك INSERT؛ تحديث إجمالي اليوم من قائمة اليوم؛ SnackBar لكل حدث | تجميع تحديثات Realtime عند وصول دفعة، وعدم إنشاء push من الشاشة |
| `lib/services/notification_service.dart` | تخزين device_tokens والاشتراك في topic خاص بالشركة/الدور | استقبال ملخص المزامنة وفتح تقريره؛ لا مفاتيح خادم داخل Flutter |
| `supabase/automatic_sale_notifications.sql` | Trigger لكل INSERT يستدعي `notify-sale` عبر pg_net | يجب دمج المسار القديم مع outbox دون مضاعفة الإشعارات |
| `supabase/functions/notify-sale/index.ts` | secret header، فحص نشاط الشركة، OAuth ثم FCM HTTP v1 إلى company admin topic | إبقاء الإرسال بالخادم؛ إعادة استخدام منطق Firebase في dispatcher |
| `supabase/saas_multitenancy.sql` | فصل company_id؛ سياسات الموظف لصفوفه؛ المدير لشركته | كل RPC وcache ودفعة يجب أن يحافظ على هذا الفصل |
| `supabase/company_access_control.sql` | تعطيل الشركة يمنع الوصول؛ profile/company status قابلان للقراءة | لا تستخدم cache لإخفاء رفض أو إيقاف مؤكد |
| `lib/core/input_limits.dart` / `supabase/input_limits.sql` | حدود النصوص والأموال 999999.99 | نفس التحقق محليًا وعلى الخادم؛ المزامنة ليست منفذ تجاوز |
| Android manifest / Gradle | INTERNET وPOST_NOTIFICATIONS، package `com.maghsala.car_wash`؛ signing release موجود | الحفاظ على الاسم والحزمة والمفاتيح وFirebase |

لا توجد مكتبة Bloc/Provider/Riverpod؛ استمر بـ StatefulWidget وChangeNotifier/ValueNotifier من Flutter. توجد تغييرات سابقة غير ملتزم بها في Git؛ لا تسترجعها ولا تستبدل الملفات بنسخة HEAD.

### نطاق التنفيذ

- يشمل إضافة مبيعات الغسيل، قراءة أنواع المركبات والأسعار، قائمة الموظف وإجمالي اليوم، تعديل/إلغاء الإضافات المحلية غير المرسلة، المزامنة وإشعارات المدير.
- لا يشمل أوفلاين السجاد أو الصور أو إنشاء الشركات أو المستخدمين أو إدارة الأسعار. تبقى هذه العمليات أونلاين مع رسالة عربية واضحة.
- لا تغيّر صلاحيات تعديل/حذف المبيعات المحفوظة على السيرفر. تعديل/حذف **الطلب المحلي غير المرسل** مختلف عن تعديل/حذف سجل مؤكد.
- المرحلة المستهدفة Android. يبقى Windows/Web على المسار الأونلاين الحالي؛ لا تستدعِ sqflite أو Workmanager عليهما. لا تنشئ مشروع iOS غير موجود.
- لا تبنِ release ولا تزد الإصدار أثناء PLAN. أثناء IMPLEMENT يكفي بناء debug والتحقق؛ إصدار المتجر خطوة إصدار منفصلة.

### قرارات ملزمة

1. **معرفان لا ترحيل هدّام:** أبقِ `sales.id bigint` و`SaleModel.id int`. أضف `client_operation_id uuid` إلى السيرفر و`localId UUID v4` لكل إضافة جديدة، أونلاين وأوفلاين. تستعمل الواجهة `LocalSale` للسجل غير المؤكد؛ لا تختلق bigint موجبًا أو تحول id إلى String في التطبيق كله. مبدأ UUID/upsert في المهارة يُطبق على مفتاح المزامنة الإضافي، لا باستبدال primary key للإنتاج.
2. **SQLite هو مصدر الطابور:** لا تستخدم SharedPreferences لطابور مالي. كل إضافة + نشاط + ربط بفترة الانقطاع في transaction واحدة؛ نجاح commit المحلي هو شرط عرض رسالة الحفظ الأوفلاين.
3. **الأموال:** خزّن قروشًا صحيحة محليًا. الحد الأعلى `99999999` قرشًا للطلب؛ decimal string على الشبكة. لا تجمع double لتوليد ملخص مالي.
4. **المزامنة:** RPCs موثوقة تتحقق من auth.uid والشركة والدور. لا ترسل Firebase من الهاتف، ولا ترسل إشعارًا لمجرد نجاح الحفظ المحلي.
5. **الدفعة:** هوية ثابتة عبر الإغلاق والمحاولات والتجزئة. عتبة 10 تخص كل الدفعة وليس حجم صفحة رفع أو عدد النتائج الناجحة.
6. **الزمن:** `created_at` وقت الإنشاء الفعلي بصيغة UTC من الهاتف، `synced_at` من الخادم. لا تستبدل الأول بوقت إعادة الاتصال. التقارير توضح الفرق واحتمال عدم دقة ساعة الجهاز.
7. **الأمان:** RLS تبقى مفعّلة. profile cache ليس تصريحًا للخادم؛ عند العودة للشبكة يفحص السيرفر حالة الموظف والشركة قبل قبول أي كتابة أو إرسال إشعار.
8. **التخزين المفصول:** كل مفتاح بيانات أعمال يحتوي user_id وcompany_id. لا تُرسل طوابير الحساب A بجلسة الحساب B حتى إذا كانا في الشركة نفسها.

## 2. أوامر الحزم — للتنفيذ لاحقًا فقط

من PowerShell داخل `D:\flutter_projects\car_wash`:

```powershell
flutter pub add sqflite path uuid internet_connection_checker_plus workmanager shared_preferences
flutter pub add --dev sqflite_common_ffi
flutter pub get
```

اختيار sqflite لأن transactions والقيود والـ lease المشتركة مطلوبة بين الواجهة وbackground isolate. إضافة shared_preferences مباشرة لازمة لاستخدام API الجلسة المشتركة؛ وجودها transitively ليس تصريحًا للاستيراد المباشر. sqflite_common_ffi لا يدخل APK؛ للاختبارات المحلية فقط.

- استخدم الإصدارات المتوافقة التي يحلها Flutter الحالي وثبّت `pubspec.lock` الناتج. لا تنفذ `pub upgrade`.
- راجع API Workmanager المحلول قبل كتابة كود التسجيل؛ لا تنسخ API قديمًا من مثال عشوائي.
- لا تضف connectivity_plus بجانب internet_connection_checker_plus دون حاجة؛ مجرد Wi-Fi ليس إثباتًا لوصول Supabase.
- لا تضف حزمة إدارة حالة أو Hive بجانب SQLite.

المراجع الأصلية: [sqflite](https://pub.dev/packages/sqflite)، [Workmanager](https://pub.dev/packages/workmanager)، [فحص الإنترنت](https://pub.dev/packages/internet_connection_checker_plus)، [أنواع رسائل Firebase](https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type).

## 3. تصميم قاعدة البيانات والخادم

### 3.1 الملفات وترتيب اعتمادها

أنشئ لاحقًا:

1. `supabase/offline_sales_sync.sql`: الأعمدة والجداول وRLS والدوال الواردة هنا، ودمج Trigger البيع.
2. `supabase/functions/_shared/firebase.ts`: استخراج OAuth/FCM من notify-sale إلى دوال مشتركة دون تضمين أسرار.
3. `supabase/functions/dispatch-sale-notifications/index.ts` و`config.toml`: عامل outbox موثوق.
4. حدّث `supabase/functions/notify-sale/index.ts` ليصبح wake-up متوافقًا مع الـ Trigger القديم، لا مسار إرسال موازٍ يتجاوز outbox.
5. `supabase/tests/offline_sales_sync_test.sql`: اختبارات transaction ثم rollback.
6. `supabase/tests/offline_notification_policy_test.sql`: ثوابت العدد والعزل ومنع التكرار.

لا تشغل schema.sql أو saas_multitenancy.sql من البداية على قاعدة الإنتاج؛ قد تعيد بذور البيانات/السياسات. استخدم هجرة إضافية واحدة بعد فحص schema الفعلية في بيئة الاختبار.

### 3.2 مخطط الجداول المستهدف

الأعمدة التالية مواصفة نهائية، وليست إذنًا لتطبيق جزء schema قبل اكتمال RPCs وحماية الحقول. جميع جداول الأعمال الجديدة تحمل company_id وemployee_id حيث يلزم.

| الجدول | الأعمدة/القيود الأساسية |
| --- | --- |
| `sales` additions | `client_operation_id uuid NULL`، `synced_at timestamptz NULL`، `offline_batch_id uuid NULL`. فهرس UNIQUE على `(company_id, client_operation_id)` للصفوف غير NULL. لا تعِد تأريخ السجلات القديمة ولا تغيّر bigint id. |
| `sale_sync_batches` | `id uuid PK`، company_id FK، employee_id FK، `device_id uuid`، `offline_started_at timestamptz`، `sealed_at timestamptz`، `expected_order_count integer >= 0`، `expected_action_count integer >= 1`، `manifest_hash text`، `state` constrained إلى receiving/processing/completed/rejected، created_at/finished_at من الخادم. UNIQUE على `(company_id,id)` لدعم FK مركب. |
| `sale_sync_items` | batch_id + company_id + employee_id، `client_operation_id uuid`، `payload jsonb`، `payload_hash text`، `state` receiving/accepted/rejected/cancelled، `sale_id bigint NULL` كمعرّف تاريخي لا cascade deletion، `error_code text NULL`، synced_at. PK `(batch_id,client_operation_id)`، UNIQUE `(company_id,client_operation_id)`، FK مركب يمنع ربط دفعة شركة أخرى. |
| `sale_sync_actions` | `id uuid PK`، batch_id/company_id/employee_id، client_operation_id، `sequence_no bigint`، action create/edit/cancel، `occurred_at timestamptz`، `before_payload jsonb NULL`، `after_payload jsonb NULL`، hash. UNIQUE `(batch_id,sequence_no)`؛ سجل append-only لا تعديل من العميل. |
| `sale_sync_receipts` | company_id + client_operation_id PK، employee_id، mode online/offline، batch_id NULL للأونلاين، payload_hash، sale_id bigint NULL، outcome accepted/rejected، error_code، server_received_at. تبقى receipt بعد حذف المدير للبيعة؛ retry لا يعيد إنشاء سجل حذفه المدير. |
| `sale_notification_outbox` | `id uuid PK DEFAULT gen_random_uuid()`، company_id، employee_id، batch_id NULL، client_operation_id NULL، `kind` online_sale/offline_sale/offline_summary، `event_key text UNIQUE NOT NULL`، title/body، `data jsonb`، state pending/processing/sent/failed/skipped، attempts integer، next_attempt_at، lease_owner UUID، lease_until، last_error، created_at/sent_at. |
| `sale_notification_deliveries` | event_id FK، token identity/hash، recipient user UUID، state pending/sent/invalid/failed، attempts، lease/next_attempt، fcm_message_name. PK `(event_id,token_identity)`. لا تجعل نجاح جهاز يخفي فشل الجهاز الثاني. |

مفاتيح event_key ثابتة مثل:

```text
online/<company_id>/<client_operation_id>
offline/<company_id>/<batch_id>/sale/<client_operation_id>
offline/<company_id>/<batch_id>/summary
```

لا تستعمل unique مع order_id NULL كوسيلة وحيدة لمنع تكرار الملخص. event_key للملخص غير NULL ومفروض بقيد UNIQUE.

### 3.3 حماية البيانات والصلاحيات

- RLS على جميع الجداول الجديدة. ألغِ افتراضيًا INSERT/UPDATE/DELETE المباشر للـ authenticated وanon. امنح authenticated SELECT على التقارير المطلوبة فقط، وEXECUTE للدوال المحددة.
- الموظف يقرأ دفعاته ونتائجها. مدير الشركة النشط يقرأ تقارير شركته؛ المشرف العام النشط حسب `public.is_super_admin()` الحالي. لا تمنح الموظف صلاحية قراءة دفعات زميله.
- جداول outbox وdeliveries للخادم فقط؛ لا SELECT لرموز أجهزة المدير من تطبيق الموظف.
- كل SECURITY DEFINER: `set search_path = ''`، أسماء schema صريحة، revoke EXECUTE من public/anon، grant للمستدعي المقصود فقط. اجعل مالك الدالة دورًا موثوقًا ولا تقبل company_id أو employee_id كحقائق دون اشتقاقهما من profiles/session.
- تحقق لكل نوع مركبة من `vehicle_types.company_id = actor.company_id` وis_active؛ FK وحده لا يكفي لمنع نوع مركبة تابع لشركة أخرى.
- تحقق role employee/admin، is_active، company.is_active؛ لا تمنح super_admin مسار تسجيل مبيعات تلقائيًا إذا لم يكن ضمن سياسة التطبيق الحالية.
- امنع العميل من كتابة `offline_batch_id` أو `synced_at` أو ربط receipt مزيفة عبر INSERT/UPDATE مباشر. Trigger حماية أو column privileges مع RPC، وليس field flag غير موثوق.
- احتفظ بمسار INSERT للأجهزة القديمة: offline_batch_id لا يقبلها إلا RPC موثوق يتحقق من عضوية batch/item. العميل القديم يظل online ولا يستطيع تعطيل الإشعارات بوضع batch_id اعتباطي.
- ادعاءات وقت الأوفلاين أو سجل التعديل من الهاتف معلومات audit غير موثقة، وليست برهانًا أن الجهاز كان غير متصل فعلًا.

### 3.4 RPCs المطلوبة — العقود وتسلسل التنفيذ المحدد

#### `submit_online_sale(operation_id uuid, payload jsonb) returns jsonb`

1. تحقق المستخدم والشركة وحدود المدخلات. اشتق employee_id/company_id؛ لا تثق بنسختهما داخل payload.
2. خذ transaction advisory lock على company+operation_id، أو receipt row lock مكافئ.
3. إن وجدت receipt: نفس hash والمالك يعيدان نفس النتيجة دون كتابة أو push جديد؛ اختلاف hash يعيد `operation_payload_conflict`. لا تعمل UPDATE على بيعة مؤكدة لمجرد retry قديم.
4. INSERT sale مع client_operation_id وcreated_at الأصلي وsynced_at=clock_timestamp. سجل receipt accepted في نفس transaction.
5. enqueue online event مرة واحدة في نفس transaction. wake-up بعد commit/pg_net، ويكفي cron لمعالجة تعطل wake-up.
6. أعد sale_id وclient_operation_id وserver_received_at والحقول اللازمة لعرض SaleModel. لا تطلب استعلام join إضافيًا باعتباره شرطًا لإثبات نجاح INSERT.

#### `begin_offline_sale_batch(batch_id uuid, metadata jsonb) returns jsonb`

- metadata: device_id، الفترة، N، عدد actions، manifest_hash، إصدار بروتوكول=1.
- تحقق المالك والنشاط وحدود أحجام المدخلات. أول استدعاء يثبت metadata، والتكرار بنفس القيم يعيد الدفعة؛ اختلاف القيم لنفس المعرف خطأ conflict لا إعادة ضبط.
- لا ترسل إشعارًا بعد begin وحده ولا تسمح بإعادة استعمال batch_id مع موظف/شركة مختلفين.

#### `stage_offline_sale_chunk(batch_id uuid, items jsonb, actions jsonb) returns jsonb`

- كل عنصر يحمل local UUID ونسخته النهائية ومعلومات cancelled، وسجل الأحداث الأصلي منفصل.
- حد النقل: 50 عنصرًا/طلب وpayload حتى 128 KiB بعد UTF-8 encoding. تقسيم النقل لا يغير N أو membership أو عدد الملخصات.
- يقبل العناصر/الأحداث idempotently بالـ hashes، ويتحقق من المالك لكل معرّف؛ اختلاف المحتوى المسبق يرفض الاستدعاء.
- احفظ في staging فقط؛ لا تنشئ sales أثناء وصول manifest غير مكتمل حتى لا يكون قرار العتبة مبنيًا على جزء من الدفعة.
- لا تقبل أحداثًا أو نسخًا جديدة بعد شروع processing أو completed.
- N = عدد create operations غير الملغاة، لا عدد أحداث create+edit ولا عدد chunks. احسبه من البيانات staged قبل بدء processing وقارنه بالعدد المثبت.

#### `seal_offline_sale_batch(batch_id uuid) returns jsonb`

- lock batch؛ تحقق من اكتمال عدد العناصر/الأحداث وmanifest hash canonical ثابت من payloads. رتب العناصر بالـ UUID والأحداث بـ sequence_no قبل حساب hash في الطرفين.
- payload canonical يستعمل مفاتيح مرتبة recursively، أموالًا integer cents، timestamps UTC normalized؛ لا تعتمد على ترتيب map أو نص jsonb::text مقابل JSON.stringify دون canonicalizer موحد واختبارات مشتركة.
- إذا الدفعة مكتملة سابقًا أعد التقرير نفسه. إذا ناقصة لا تنشئ مبيعات أو ملخصًا.
- يثبت N من manifest ويحول state إلى processing؛ ثم يستدعي معالجة الصفحة الأولى.

#### `process_offline_sale_batch(batch_id uuid, limit_count integer DEFAULT 50) returns jsonb`

- lock batch يمنع عمل صفحتين متداخلتين. لا تمسك transaction أثناء استدعاء Firebase أو HTTP.
- لكل عنصر غير نهائي: إن cancelled احتفظ بالنشاط بلا sale. إن receipt موجودة أعد النتيجة دون إعادة INSERT، حتى لو حذف المدير sale لاحقًا.
- في subtransaction لكل عنصر: تحقق النوع والحدود ثم احفظ sale + receipt + item accepted في transaction واحدة. الأخطاء الدائمة المتوقعة تحفظ rejected مع error_code عربي قابل للعرض. خطأ بنية قاعدة البيانات/انقطاع/خطأ غير مصنف يرفع الاستثناء ويؤدي retry، ولا يصنف جميع العناصر رفضًا دائمًا.
- notification decision مبني على N المثبت. إن 1<=N<=10 أضف offline_sale لكل accepted فقط. إن N>10 لا تضف أي offline_sale حتى لو لم ينجح إلا عنصر واحد.
- عند انتهاء جميع العناصر: احسب إجمالي القروش من القيم النهائية accepted فقط، وعدد المرفوض/الملغى والتعديلات، ثم أنشئ offline_summary واحدًا وأكمل batch في نفس transaction. فشل الشبكة بين الصفحات يترك الدفعة processing بلا ملخص نهائي مبكر.
- لو كل الطلبات مرفوضة أو كلها ملغاة ولديها نشاط: ملخص واحد يشرح ذلك، بدون ادعاء مبيعات ناجحة.
- لو الشركة أصبحت inactive أثناء المعالجة: امنع كتابة عناصر جديدة والإشعارات؛ احتفظ بحالة blocked/retry عند إعادة التفعيل بدل تسريب بيانات أو حذف طابور الهاتف. حالة الوصول المنعكس تظهر للموظف؛ لا تعاود retry بشكل محموم.

#### `get_offline_sale_batch_report(batch_id uuid) returns jsonb`

- يتحقق من صلاحية القارئ قبل أي بيانات. يعيد header والتفاصيل paginated إذا لزم الأمر، لا نصًا ضخمًا غير محدود.
- التقرير يشمل جميع الإضافات وتتابع التعديلات والإلغاءات ونتائج الخادم وأوقات الإنشاء/الاستلام والفروق. لا يكرر قيمة طلب لمجرد تعديله عدة مرات.
- هذا التقرير هو وجهة الضغط على push، وليس data payload ضخمًا.

### 3.5 استبدال مسار Trigger والإرسال بأمان

1. في الهجرة، أنشئ enqueue function واحدة يستدعيها مسار online وRPCs. المفتاح الفريد يضمن أن المرور من trigger وRPC لا ينشئ حدثين.
2. legacy INSERT بلا client_operation_id يحصل event_key مبنيًا على sales.id القديم؛ لا تعِد إصدار إشعارات لتاريخ المبيعات كله.
3. لا تجعل `notify_admins_after_sale_insert()` يرسل FCM مباشرة بعد تعديل النظام. يصبح دوره جدولة حدث online أو wake-up فقط. الـ offline insert لا يولد online event إذا تحقق الخادم من receipt/item وربط العملية المؤكد.
4. حدّث `notify-sale` بحيث يتعامل مع wake-up الموثوق، ولا يقبل record يحدده العميل كمرجع كافٍ لإرسال arbitrary push. لا يوجد مساران مستقلان للإرسال لنفس event_key.
5. authentication للعامل: secret خادمي جديد `SALE_OUTBOX_DISPATCH_SECRET` في Supabase secrets وVault. لا تخزنه في SQL ملتزم بـ Git أو في Flutter أو ملف الخطة. أعد استخدام FIREBASE_SERVICE_ACCOUNT_JSON الموجود بدل إنشاء حساب Firebase جديد.
6. جدول دوري عبر Supabase Cron كل دقيقة يستدعي dispatcher؛ pg_net wake-up مجرد تحسين latency. توقيت SQL scheduler وVault secrets خطوة إعداد لا تتجاوزها بادعاء أن الجدولة تعمل تلقائيًا.
7. dispatcher يحجز events/recipient deliveries بـ `FOR UPDATE SKIP LOCKED` وlease ثلاث دقائق، ويحدث النتائج بlease_owner مطابق. حد التشغيل 20 event أو 40 ثانية ثم يكمل الاستدعاء التالي.
8. قبل الإرسال أعد التحقق من الشركة النشطة ومن المستلمين: `profiles.role='admin'`، profile.is_active، company_id مطابق، device_tokens.user_id/company_id مطابق. إرسال جديد مباشر إلى tokens المصرح بها لتقارير الأوفلاين، لا topic عام قابل للاشتراك من أي عميل.
9. إذا لا يوجد جهاز مسجل: سجل waiting recipient مع retry bounded؛ التقرير يبقى متاحًا من داخل التطبيق. عدم وجود token لا يعني نجاح تسليم.
10. عند 401 من Google أعد تجديد OAuth مرة واحدة؛ عند 429/5xx استخدم backoff وRetry-After. عند UNREGISTERED علّم token invalid واحذفه فقط إذا ما زال مرتبطًا بنفس identity. لا تحذف token عند خطأ إعدادات عام.
11. عدد المحاولات 8، وتأخير تصاعدي من 30 ثانية إلى 30 دقيقة، وبعدها failed قابل للمراجعة. لا تعِد إرسال الأجهزة التي لها sent عند فشل جهاز آخر.
12. تنسيق عربي مختصر؛ FCM `notification` + `data` وبحد محافظ إجمالي للحمولة أقل من 4096 بايت (احسب UTF-8، لا عدد الحروف). `data` يحتوي event_id/type/company_id/batch_id فقط وما يلزم للتوجيه؛ لا تفاصيل شخصية أو كلمات مرور.
13. Android notification tag = event_id ثابت. لا تستخدم نفس tag لكل فردي وإلا ستستبدل 10 إشعارات بعضها بعضًا. summary tag منفصل عن الفردي. لا تضع collapse_key موحدًا لكل الطلبات.
14. لا يوجد ضمان exactly-once من FCM: قد يحدث تعطل بعد قبول Google وقبل تحديث outbox. الثابت المضمون هو logical event واحد بالسيرفر؛ stable IDs وdedup تقلل تكرار العرض، ولا يجوز وصف HTTP200 بأنه إثبات وصول للهاتف.

### 3.6 سياسة العدد — مصفوفة ثابتة

| N الأصلي | accepted عند اكتمال الدفعة | الفردي | الملخص | الإجمالي المنطقي |
| --- | --- | --- | --- | --- |
| 1 | 1 | 1 | 1 | 2 |
| 3 | 3 | 3 | 1 | 4 |
| 10 | 10 | 10 | 1 | 11 |
| 11 | 11 | 0 | 1 | 1 |
| 11 | 5 | 0 | 1 يوضح 5 ناجحة و6 مرفوضة | 1 |
| 3 | 2 | 2 | 1 يوضح الرفض | 3 |
| 3 | 0 | 0 | 1 يوضح الرفض | 1 |
| 0 مع أحداث إلغاء | 0 | 0 | 1 | 1 |
| لا أحداث أصلًا | 0 | 0 | 0 | 0 |

الملخص الواحد في حالة N>10 هو نفسه الملخص الإلزامي؛ ليس هناك إشعار تجميع إضافي. العدد لكل مدير/جهاز، لا مجموع HTTP requests إلى كل أجهزة الشركة.

## 4. إعدادات المنصات والجلسة

### Android

أضف فقط سطر الإذن التالي إلى manifest مع الإبقاء على باقي الملف:

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

- احتفظ بـ INTERNET وPOST_NOTIFICATIONS والاسم والأيقونة والحزمة وتوقيع الإصدار وgoogle-services.json.
- Workmanager يوفر مكونات Android الافتراضية عبر manifest merger؛ لا تضف Application subclass أو خدمة foreground أو boot receiver يدويًا دون أن تتطلب النسخة المحلولة ذلك.
- افحص merged manifest في debug للتأكد من مكونات WorkManager والـ network constraint. لا تضف SCHEDULE_EXACT_ALARM أو battery exemption أو foreground-service permissions لهذه المهام القصيرة.
- Android backup: استبعد قاعدة queue وأسرار الجلسة من cloud backup/device-transfer، أو عطّل backup لهذه البيانات باستخدام data extraction rules. استرجاع queue قديمة إلى جهاز جديد لا يجب أن يبعث تاريخ مبيعات كأنه جديد. طبق القواعد مع الحفاظ على ملفات البيانات الحالية، وليس حذفها.
- لا تشغيل مضمون بعد Android force-stop حتى يفتح المستخدم التطبيق؛ test cold-start يعيد فتحه صراحة. swipe-away/Doze/OEM restrictions قد تؤخر worker. الرفع الفوري عند الاتصال متاح أثناء عمل التطبيق، والخلفية best-effort.

### iOS / Windows / Web

لا يوجد ios/Runner في المشروع الحالي؛ **لا تنشئ Info.plist** لهذه المهمة. إذا أضيف iOS لاحقًا، يخطط BackgroundTasks/APNs setup كعمل منفصل. على Windows/Web تبقى الواجهة والسلوك الأونلاين الحاليان مع تعطيل offline runtime بدل MissingPluginException.

### جلسة Supabase عبر isolates

- أول دخول أو دخول مستخدم جديد يحتاج شبكة. لا تخزّن كلمة المرور إطلاقًا.
- هوية الحساب من جلسة Supabase المحلية، والملف/الشركة من cache مطابق محفوظ بعد استجابة ناجحة ومؤرخة. لا تعتمد على email أو اسم لإسناد queue.
- استخدم storage adapter واحدًا للجلسة يعتمد `SharedPreferencesAsync`، لا SharedPreferences cached داخل isolates. هيئ foreground وworker على **نفس namespace/key الموجود فعليًا**؛ هجرة حفظ الجلسة تقرأ المفتاح القديم أولًا ولا تسجل خروج جميع المستخدمين.
- أي refresh/recoverSession/signOut يستخدم lease خاص auth في SQLite. لا تشغل auto-refresh مستقلًا في worker ينافس foreground. اضبط foreground إذا لزم بحيث كل مسار refresh يمر بنفس المنسق، واختبر استدعاءات Supabase الضمنية بدل افتراض تعطيلها.
- قبل الرفع اقرأ أحدث serialized session من disk، recoverSession تحت القفل ثم refresh إذا expired أو أقل من 60 ثانية للانتهاء. لا تحاول refreshSession عندما لا توجد refresh token؛ أوقف المزامنة واطلب إعادة الدخول للحساب نفسه مع الاحتفاظ بالطابور.
- عند عودة worker وتحديث session، foreground يعيد تحميلها عند resume وقبل الطلب التالي. لا يسجل القديم فوق الجلسة الأحدث؛ استعمل session revision محفوظة.
- تغيير المستخدم أو logout يزيد session_epoch. أي طلب جارٍ يتحقق من epoch/owner قبل حفظ cache أو عرض بيانات أو مواصلة صفحة أخرى. طلب قُبل بالفعل بالسيرفر لا يمكن إلغاؤه محليًا؛ يظل باسم صاحبه الصحيح.

## 5. خطة ملفات Flutter والعقود التفصيلية

هذه الأقسام تحدد أسماء الملفات والمسؤوليات والحالات وتسلسل الدمج. لا تحوّلها إلى ملفات فارغة أو دوال وهمية أثناء IMPLEMENT. يجب أن تكون جميع المسارات والدوال التالية مكتملة ومختبرة قبل الادعاء باكتمال التنفيذ.

### 5.1 `[CREATE] lib/models/local_sale.dart`

- `LocalSale`: localId UUID، ownerUserId، companyId، serverId int?، vehicleTypeId int، snapshot الاسم والأيقونة واسم الموظف، priceCents int، vehicleName/plateNumber/notes، createdAt UTC، syncedAt UTC?، batchId UUID?، syncState enum، errorCode/errorMessage?، revision int، firstAttemptAt?، nextAttemptAt?، notificationOrigin online/offline/uncertain.
- حالات syncState: pending، frozen، syncing، synced، failed، cancelled، needsAuthentication، blockedAccess. `notificationState` منفصل: notScheduled/queued/acceptedByProvider/failed؛ لا تعادل synced بـ «وصل إشعار المدير».
- fromMap/toMap/copyWith null-safe؛ mapping SQLite→JSON وremote sale→LocalSale محددان. من السيرفر اربط client_operation_id إن وجد، وإلا key `server:<company>:<id>` للصفوف القديمة.
- لا تجعل pending.id = 0 ثم ترسله لـ updateSale. شاشة التفاصيل تميز LocalSale عن SaleModel؛ serverId لازم قبل أي عملية على جدول sales مباشرًا.
- date grouping يستخدم toLocal للعرض وحدود اليوم؛ اجعل الوقت injectable للاختبارات. لا تتلف createdAt عند تعديل السعر.

### 5.2 `[CREATE] lib/models/offline_sync_batch.dart`

- immutable id/owner/company/device/startedAt/sealedAt، expectedOrderCount/actionCount، manifestHash، phase draft/frozen/staged/processing/completed، عناصر+أحداث بمعرفات مستقرة.
- N يحسب بعد collapse edits والطرح cancellations، ويثبت عند freeze. حفظ manifest/hash وpayload snapshots داخل transaction.
- أي نشاط جديد بعد freeze ينتمي لفترة/دفعة جديدة؛ لا تضفه إلى manifest مرسل جزئيًا. هذا لا يسمح بتقسيم ما كان في نفس snapshot إلى دفعات نقل أصغر لتغيير العتبة.
- batch متعطلة تبقى بنفس UUID، حتى بعد إعادة تشغيل التطبيق أو تغيير عدد chunks أو انتهاء lease.

### 5.3 `[CREATE] lib/services/offline_store.dart`

قاعدة `maghsala_offline_v1.db` في application-private database directory، SQLite schema version=1، foreign_keys=ON، transactions قصيرة؛ لا تنتظر HTTP داخل transaction. حافظ على onUpgrade migrations لاحقًا.

الجداول المحلية النهائية:

| الجدول | المفتاح والبيانات |
| --- | --- |
| `cached_profiles` | `(user_id, company_id)` PK، JSON ProfileModel، verified_at، revoked_at NULL، session_epoch |
| `cached_vehicle_types` | `(user_id,company_id,type_id)` PK، JSON، fetched_at. استبدال snapshot النشط transactionally |
| `cached_sales` | `(user_id,company_id,merge_key)` PK، JSON مؤكدة فقط، fetched_at؛ لا تمسح queue عند refresh |
| `pending_sales` | local_id PK، owner+company، payload JSON، price_cents، created_at، state/revision، server_id، batch_id، next_attempt_at، last_error |
| `offline_episodes` | id PK، owner+company+device، started_at، frozen_at، N/actions/hash، phase، server batch status |
| `offline_activity` | event_id PK، episode_id، local_id، sequence_no، kind، before/after JSON، occurred_at؛ UNIQUE episode+sequence |
| `sync_leases` | scope PK، owner UUID، expires_at epoch-ms، fencing_token متزايد |
| `app_metadata` | key PK، JSON value؛ device UUID، session_epoch، cached update policy+verified_at |

العمليات العامة المطلوبة:

- `enqueueSale(...)`: تحقق InputLimits ومطابقة owner؛ أنشئ UUID مرة واحدة؛ transaction تحفظ pending والنشاط والepisode؛ return بعد commit فقط.
- `editPending(localId, expectedRevision, fields)` / `cancelPending(...)`: يسمح فقط pending لم تُرسل ولم تتجمد؛ يزيد revision ويضيف event. cancelled يبقى في audit ولا يظهر كمبيعات. conflict يطلب refresh ولا يستبدل تعديلًا أحدث.
- `freezeEpisode(...)`: atomic snapshot؛ لا يسمح edits بعد بدء المحاولة. إظهار حالة «جار التحقق من المزامنة» بدل السماح بحذف سجل ربما حفظ على الخادم.
- `readQueue(owner,company)` / `readTodayMerged(...)`: لا query عام بلا owner/company. pending قديمة لها قسم «عمليات في انتظار المزامنة» حتى لا تختفي عند منتصف الليل؛ ليست شاشة مبيعات سابقة للموظف.
- `replaceRemoteToday(...)`: فقط refresh كامل ناجح يستبدل cached today ضمن الحدود المطلوبة. فشل الشبكة لا يعني قائمة فارغة.
- `markServerResult(...)`: transaction تربط local UUID بالbigint وتبدل الحالة وتحدث cache دون duplicate. نجاح INSERT مع فشل response لا يغير النتيجة بعد reconciliation.
- `acquireLease(scope, owner, ttl)` / `renewLease(...)` / `releaseLease(...)`: atomic conditional insert/update داخل transaction، renewal/release بشرط owner+fencing token. TTL دقيقتان، renew كل 20 ثانية، network timeout 15 ثانية؛ worker لا يستمر إذا فقد fencing token.
- `clearIdentityCaches(...)`: فصل caches عند logout دون حذف pending غير مؤكدة. تبقى مخفية وملكية immutable؛ لا تنتقل للمستخدم التالي.
- stream/notifier لتغيرات foreground؛ worker لا يرسل notifyListeners في isolate أخرى. أعد قراءة SQLite عند resume/اكتمال العمل/تحديث دوري خفيف أثناء وجود pending.
- عند full disk/فشل commit: رسالة «تعذر الحفظ على الهاتف»، لا success ولا navigate وكأن البيع محفوظ.

### 5.4 `[CREATE] lib/services/offline_session_service.dart`

- تحميل cache بعد تطابق userId من الجلسة المحفوظة. profile verified active وcompany active، role employee فقط لفتح تسجيل أوفلاين في هذه المرحلة.
- صلاحية offline grant المحلية: 7 أيام من آخر تحقق ناجح؛ تسمح cold-start اليوم التالي، ولا تستمر بلا نهاية. تجاوزها: شاشة عربية تطلب اتصالًا لتأكيد الحساب، مع الاحتفاظ بالطابور.
- known inactive/revoked يمنع فورًا حتى offline. لا يُستبدل آخر رد منع بcache أقدم active. أول مستخدم/لا cache/حساب شركة أخرى لا offline access.
- فقد الشبكة != صلاحيات: timeout/socket يبقي grant ضمن مدته، أما response confirmed inactive/401 refresh revoked/403 فلا يُخفى بcache.
- بعد الإنترنت، تحقق profile/company قبل إرسال pending. suspended→blockedAccess، expired auth→needsAuthentication، رجوع حالة نشطة/دخول نفس صاحب البيانات يسمح retry لا إعادة إسناد.
- لا تدّعِ معرفة تعطيل الشركة أثناء انقطاع الشبكة؛ السيرفر يمنع قبول الطابور عند العودة. حفظ محلي ليس قبولًا ماليًا بالخادم.
- logout: إن pending موجودة اعرض عددها وتحذيرًا مع خيار الرجوع. عند تأكيد logout احتفظ بها محليًا مفصولة، أوقف watchers/tasks الخاصة بالمستخدم ولا تسربها لحساب آخر. لا حذف تلقائي لخسارة مالية.

### 5.5 `[CREATE] lib/services/offline_sales_repository.dart`

- يعتمد SupabaseClient وOfflineStore وOfflineSessionService والوقت، injectable في الاختبارات. لا يعتمد على Widgets أو NotificationService أو build context.
- `createSale(...) -> Future<LocalSale>`: validate؛ local commit أولًا؛ إذا network reachable حاول submit_online_sale بمعرف العملية نفسه ضمن timeout؛ وإلا return pending وschedule sync. لا تجعل نجاح الشبكة شرطًا لنجاح حفظ الأوفلاين.
- الإنترنت checker استرشادي؛ فشل Supabase الفعلي هو المرجع. لا تصنف HTTP500 كرفض دائم ولا HTTP403 كأوفلاين.
- لو حاول online ثم ضاع الرد: pending_uncertain، لا تنشئ UUID جديدًا أو إشعارًا جديدًا. عند reconnect ابحث receipt أولًا؛ إن accepted أعد الارتباط واحتفظ origin online ولا تدخله ثانية في إجمالي الملخص. إن ثبت عدم وجوده، أدخله كإنشاء أوفلاين في snapshot. لا تسمح edit/cancel أثناء عدم اليقين.
- `getTodaySales()`: cache أولًا؛ refresh ناجح من Supabase بعد session ensure؛ merge بالclient_operation_id ثم fallback server id؛ filtered by owner/company وlocal day start/end. لا تضاعف rows عندما ينجح الرفع قبل إزالة pending.
- `getTodayTotal()`: fold priceCents للصفوف المرئية مرة واحدة. failed/cancelled لا تدخل الإجمالي؛ pending تدخل بإشارة أن الإجمالي يتضمن غير متزامن. synced تعني confirmed فقط.
- `getPendingOlderThanToday()`: قسم متابعة منفصل حتى لا تضيع طلبات أمس غير المرفوعة؛ لا يمنح الموظف تاريخ مبيعات الخادم.
- `updatePending`/`cancelPending` محليان فقط قبل freeze، ويحترمان revision. التعديل على synced يمر SalesService الأصلي وبصلاحياته وأونلاين.
- أسعار النوع snapshots؛ لا تُعد تسعير بيع مسجل أمس تلقائيًا عند تحميل أسعار جديدة. active type مرفوض اليوم ينتج failure قابل للمراجعة، لا mapping صامت لنوع آخر.

### 5.6 `[CREATE] lib/services/offline_sync_service.dart`

- خدمة واحدة لكل runtime، ChangeNotifier مدمج؛ dispose صريح للـ subscriptions/timers. الواجهة تستمع للقراءة فقط.
- triggers: internet status becomes connected، app resume، manual sync، background task، بعد enqueue عند الشبكة. mutex in-memory + lease SQLite مطلوبان، لا يكفي bool عبر isolates.
- قبل أي طلب: تحقق owner/session_epoch/lease؛ refresh/recover under auth coordinator؛ online profile/company؛ minimum-version decision.
- reconcile uncertain operations أولًا؛ freeze draft episodes، ثم begin/stage chunks/seal/process حتى completed أو budget 40 ثانية. resume من stored phase، لا تعِد إصدار episode id.
- pagination limit50 و128KiB؛ chunk manifest يبقى ثابتًا. batch retry بعد network loss لا يغير N.
- بعد كل نجاح، markLocalResults transactionally ثم notify. pending المجدولة لا تختفي عند timeout. سرعات رفع متتالية bounded لا Parallel Future.wait غير محدود.
- أخطاء مؤقتة: timeout/socket/HTTP429/5xx → pending، exponential backoff 5s..5min وjitter، بحد 8 محاولات آلية قبل حالة تحتاج إعادة محاولة يدوية. حافظ على البيانات؛ لا busy loop.
- 401 refresh transient لا يساوي invalid_refresh_token. terminal invalid refresh→needsAuthentication، 42501/confirmed forbidden→blockedAccess أو failed حسب سبب محدد، 22001/22003/23503 expected validation→failed مع رسالة عربية. unknown SQL errors ترفع لإصلاح schema ولا تُبتلع.
- operation failed لا يعاد إرسالها حتى قرار المستخدم؛ retry لخطأ قابل للإصلاح ينشئ revision/محاولة موثقة وفق protocol ولا يغير manifest سبق قبوله. لا تعدل payload receipt قديمة بعد freeze؛ correction بعد rejection يكون عملية جديدة مرتبطة بالأصل وتقرير واضح، لا sale duplicate صامت.
- budget انتهى مع بقية صفحات: schedule continuation، لا تلخص كأن الرفع انتهى.
- تتبع upload progress وlastSuccessfulSyncAt وpending/failed counts؛ لا تتبع Firebase عبر الهاتف لإعادة بيع تم حفظه.

### 5.7 `[CREATE] lib/services/offline_background_service.dart`

- callbackDispatcher top-level بـ `@pragma('vm:entry-point')`؛ WidgetsFlutterBinding.ensureInitialized، DartPluginRegistrant.ensureInitialized إذا تطلبت نسخة plugin، ثم تهيئة store/session/client دون runApp أو Firebase receiver غير لازم.
- لا استدعاء main() لأنه يعيد إنشاء واجهة وsubscribers.
- unique task لكل user+company، NetworkType.connected، ExistingWorkPolicy.keep/المكافئ في النسخة المحلولة، backoff تصاعدي. one-off بعد أول enqueue، recovery periodic لا يقل عن الحد الذي تسمح به المنصة. توقيت دوري ليس instant.
- worker يأخذ user/company/epoch كمدخلات غير سرية؛ لا password/token داخل inputData أو logs. يقرأ الجلسة الحالية ويفشل مغلقًا عند mismatch.
- إذا المستخدم logged out أو تبدل epoch: no-op ناجح ويحتفظ بالطابور لصاحبه، لا يعاود الأبد. network transient يعيد failure/retry المحدود؛ permanent يرجع task complete مع حفظ حالة يحتاج تدخل.
- main foreground يعرف أن هناك عملًا pending عند startup/resume ويعيد تسجيله إذا لزم؛ قتل العملية لا يمس durable queue.

### 5.8 `[CREATE] lib/widgets/offline_sync_status.dart`

- Banner عربي: «أنت غير متصل — تُحفظ العمليات على هذا الهاتف حتى عودة الاتصال».
- online+pending: «توجد X عمليات في انتظار المزامنة» مع زر أيقونة sync وtooltip «مزامنة الآن»، spinner أثناء العمل ومنع الضغط المكرر.
- offline grant expired / needs auth / suspended رسائل مميزة وليست زر retry لا نهائي.
- row status: cloud_done أخضر «تمت المزامنة»، cloud_upload برتقالي «في انتظار المزامنة»، sync أزرق أثناء العمل، error أحمر «تعذر المزامنة» مع السبب/retry إن مسموح.
- لا تعرض «أُرسل للمدير» بمجرد synced. حالة push منفصلة ولا حاجة لعرضها للموظف كأنها وصول مؤكد.
- Pending local row يدعم edit/cancel قبل freeze مع confirmation وundo إذا آمن. أثناء frozen/uncertain عطّل edit/cancel برسالة السبب.
- layout Wrap/Flexible ثابت الأيقونات، يعمل320px وRTL وخط مكبر؛ لا تغيير حجم كارت بسبب spinner.

### 5.9 `[CREATE] lib/screens/offline_sync_report_screen.dart`

- معامل batchId، service injectable؛ تحميل get_offline_sale_batch_report بصلاحيات المستخدم لا service role.
- header الموظف/الفترة/عدد ناجح-مرفوض-ملغى/الإجمالي النهائي؛ قائمة paginated للطلبات وتاريخ النشاط؛ أوقات client/server ظاهرة بالعربية.
- loading/error/retry/pull-refresh ورفض صلاحية واضح. لا cache تقرير شركة لحساب شركة أخرى.
- اسم الصفحة «ملخص العمليات بدون إنترنت». لا تضع كل التفاصيل داخل notification payload.

### 5.10 `[MODIFY] lib/main.dart`

- بعد binding وقبل runApp افتح store على Android فقط، وهيئ session adapter، ثم Supabase. أخطاء store لا تُخفيها؛ اعرض خطأ initialization/retry بدل فقد بيانات صامت.
- احتفظ بـ Firebase.initializeApp وfirebaseMessagingBackgroundHandler الحاليين. تهيئة Workmanager لا تحل محل Firebase handler.
- runtime instance واحدة، onAuthStateChange يربط/يفصل owner وepoch. لا listeners مكررة عند إعادة build MaterialApp.
- router/navigationKey واحدة لدعم notification tap، مع pending route queue حتى اكتمال auth/company checks. ممنوع فتح report قبل login أو فوق suspended/update required.
- حافظ RTL/theme وAppVersionLabel. لا تغيّر applicationId أو app name.

### 5.11 `[MODIFY] lib/services/auth_service.dart` و`lib/screens/auth_gate.dart`

- getCurrentProfile online الناجح يخزن ProfileModel + verifiedAt؛ lookup cache يطابق user/company ولا يخلق default company فارغة قابلة للتسجيل.
- لا تجعل catch العام في `_checkAuthentication()` يدفع المستخدم لشاشة Login عند network failure. فرق network/unavailable عن revoked session وعن profile مفقود مؤكد.
- على cold-start offline: grant صالح→HomeScreen الموظف بالملف المحفوظ، لا register token HTTP حاجب؛ لا login بدون session سابقة.
- يحتفظ auth gate باشتراك الشركة وpoll الحاليين عند توفر الشبكة؛ حين يؤكد تعطيلًا أوقف upload، حدّث cache ممنوع، وأغلق routes غير آمنة كما يفعل الآن.
- last verified active لا يعاد كتابته إلى true من profile cache بعدما سجلت suspension. profile ownership تغير أثناء await→discard result.
- admin/superadmin opening offline ليس صلاحيات إدارية محلية جديدة؛ اعرض network-required أو cached read-only محدد، ولا تمكن إدارة الشركات/الحسابات والأسعار من cache.
- logout عبر session coordinator، pending warning قبل call، cleanup token best effort بtimeout، احتفظ spinner الموجود.
- AuthService tests التي تمرر SupabaseClient وهمي تبقى قابلة للاختبار دون global singleton؛ dependency injection للـ store/session coordinator.

### 5.12 `[MODIFY] lib/services/app_update_service.dart` و`lib/widgets/app_update_gate.dart`

- get raw `AppUpdatePolicy` دائمًا واحفظ enabled/minimumBuild/updateUrl/verifiedAt؛ لا تخزن null باعتباره نفس الشيء كفشل الشبكة.
- حد cache سياسة التحديث 7 أيام (نفس offline grant) عند عدم توفر الشبكة؛ كلاهما مطلوب للأوفلاين. لا شبكة ولا cache ناجحة→شاشة retry لا تجاوز لأول تشغيل.
- known requiresUpdate يبقى blocking offline. latest successful policy allows current build + valid employee grant يسمح cold-start، مع إعادة التحقق على resume/reconnect.
- لا تعامل response403/invalid policy كإجازة، ولا تمسح update block عند timeout. عند إعادة الاتصال وفشل التحقق من الحد الأدنى، لا ترفع pending جديدة حتى تحقق ناجح؛ تبقى محفوظة.
- emergency disable لا تُفترض محليًا؛ تؤخذ من response ناجحة. أبقِ bottom-right version label وstore link وفحوص AppUpdateGate الحالية.
- offline allow is intentionally different from startup fail-closed الحالي؛ عدّل الاختبارات والوثيقة APP_UPDATES.md لتشرح قيد cache الموثوقة بدل ادعاء أنه نفس السلوك السابق.

### 5.13 `[MODIFY] lib/services/vehicle_type_service.dart`

- أضف cache-first لمسار قراءة الأنواع النشطة للموظف عبر OfflineStore، مع background refresh غير حاجب.
- حفظ قائمة ناجحة empty يسمح إظهار «لا توجد أنواع متاحة»؛ فشل الطلب لا يمسح قائمة سابقة.
- snapshot keyed user+company؛ لا stale types شركةA في form شركةB. admin getVehicleTypes/create/update/uploadIcon تبقى online.
- لا تعدل أسعار بيع معلق عند تغير النوع. remote inactive لا يسمح sync بربط نوع شركة أخرى؛ يعيد error قابل للعرض.
- أيقونات HTTP قد لا تكون cached على disk؛ استخدم Material fallback الحالي عند offline ولا توقف الفورم بسبب فشل صورة.

### 5.14 `[MODIFY] lib/services/sales_service.dart` و`lib/models/sale_model.dart`

- احتفظ public signatures الحالية المستخدمة في AdminHomeScreen/PreviousSalesScreen واختبارات input limits. أضف optional clientOperationId/syncedAt إلى SaleModel مع defaults للخرائط القديمة؛ أبقِ id int.
- المسار الجديد للموظف يستعمل OfflineSalesRepository وLocalSale؛ لا يكسر return SaleModel الحالي بإرجاع pending على أنها confirmed.
- getTodaySales للمدير يظل استعلام سيرفر؛ إضافة repository منفصلة تمنع admin seeing employee cache. دوال delete/update/getPreviousSales لا تصبح offline queue في هذا النطاق.
- network exceptions تمر typed إلى repository؛ لا تلف PostgrestException في Exception عام قبل تصنيفه.
- .upsert/ON CONFLICT على client_operation_id عن طريق RPC، لا INSERT جديد كل retry ولا overwrite سعر مؤكد سابق عند وصول نسخة قديمة.
- التاريخ: استخدم startLocal=DateTime(y,m,d)، endLocal=DateTime(y,m,d+1)، ثم toUtc في فلاتر timestamptz. لا end=start.add24hours عند حدود DST. الوقت الافتراضي Africa/Cairo مع تحقق/تحذير عند اختلاف إعداد الهاتف إن أضيف، ولا تدّعِ أن الساعة المحلية دليل موثوق.

### 5.15 `[MODIFY] lib/screens/add_sale_screen.dart`

- إضافة مسار معامل LocalSale? مستقل عن SaleModel?؛ لا يقبل كليهما. synced SaleModel edit يبقى مساره الحالي.
- تحميل cached types فورًا؛ selection والسعر وكل InputLimits وMoneyInputFormatter الحالية محفوظة.
- create يمر repo local commit، مع duplicate-submit guard منذ الضغط حتى اكتمال commit، وUUID ثابت للمحاولة. بعد commit رسالة «تم الحفظ على الهاتف وسيتم الإرسال عند الاتصال» إن pending، أو النجاح الحالي إن confirmed.
- فشل التخزين: ابقَ في الشاشة مع قيم الحقول ولا تعرض success. sync failure بعد commit ليس سببًا لأن يعيد المستخدم إنشاء البيع نفسه.
- pending edit يعرض النسخة الحالية وexpectedRevision. pending cancel في صفحة الموظف بتأكيد؛ لا يسمح بالتعديل بعد frozen/uncertain.
- inject repository/type loader/auth service للـ tests دون تغيير حزمة إدارة الحالة.

### 5.16 `[MODIFY] lib/screens/home_screen.dart`

- استبدل employee-only مصدر القائمة بـ merged LocalSale view models؛ أبقِ DashboardHeader/DashboardSummary/SaleTile/VehicleIcon/format helpers العامة حتى لا تنكسر شاشات المدير والسجاد.
- الملف الشخصي المحفوظ يُعرض دون Future.wait شبكة حاجب. بعد نجاح online refresh حدّث الاسم/الشركة في cache.
- listen واحد لخدمة المزامنة، unsubscribe dispose؛ initial local load ثم background remote refresh. pull-to-refresh يحاول sync/refresh ويحتفظ بالبيانات عند offline.
- إجمالي اليوم وعدده من نفس merged list بلا تكرار. وضح وجود pending في سطر الحالة، لا تخلط cancelled/failed في الإجمالي.
- أضف OfflineSyncStatus أسفل header؛ وحالة كل صف. قسم «عمليات في انتظار المزامنة» لpending من أيام سابقة مع date واضح، بدون منح read لمبيعات أمس المؤكدة.
- edit/cancel/retry controls حسب الحالة، loading/error/empty الحالية تبقى بالعربية. لا ترجع spinner شاملًا يخفي cache في كل محاولة خلفية.
- عرض السجاد يبقى online؛ إن ضغط عليه offline تظهر رسالة «طلبات السجاد تحتاج اتصالًا بالإنترنت حاليًا» بدل شاشة فشل مبهمة.
- حافظ زر إضافة مركبة والـ logout spinner والـ RTL. راجع narrow layout320px.

### 5.17 `[MODIFY] lib/screens/admin_home_screen.dart`

- subscribe name/filter الشركة الحالية، واحدة لكل screen. debounce INSERT burst250ms ثم fetch؛ إذا حدث جديد أثناء fetch ضع refreshAgain=true حتى لا تُفقد آخر البيعات.
- Realtime يعني تحديث البيانات وليس إرسال push. لا duplicate push بسبب فتح لوحة المدير.
- حافظ إجمالي اليوم فقط في الصفحة الرئيسية؛ بيع offline مسجل أمس يظهر في previous sales بتاريخ created_at الحقيقي، لا ضمن إجمالي اليوم لمجرد وصوله اليوم.
- اعرض مدخل «ملخصات المزامنة»/latest summaries لمدير الشركة حتى يصل للتقارير إذا رفض الإشعارات أو لم يسجل token. الصفحة تعتمد server report RLS.
- احذف SnackBar لكل INSERT burst واستبدله برسالة واحدة مناسبة للـ refresh؛ لا تغيّر سياسة push N+1 المعتمدة؛ in-app snackbar ليس push إضافيًا.

### 5.18 `[MODIFY] lib/services/notification_service.dart`

- استمع لـ `FirebaseMessaging.onMessageOpenedApp` و`getInitialMessage` وforeground onMessage مرة واحدة؛ route إذا type=offline_sale_summary وbatch_id صالح، بعد تحقق current profile/company. routes القادمة قبل login تحفظ مؤقتًا ثم تتحقق من جديد.
- stable event_id للـ dedup، وreport fetched بصلاحيات مستخدم حالي. لا تثق بأن payload يصرح بالدخول لتقرير شركة أخرى.
- foreground يظهر in-app feedback مناسب ويحدث inbox؛ النظام يعرض notification في الخلفية. لا تنشئ local system notification ثانية فوق system-rendered push.
- أبقِ إشعارات signup requests/super_admin خارج تغيير مبيعات الغسيل؛ لا تلغِ tokens أو topics لها عرضيًا.
- استقبال تقرير على حساب مختلف بعد logout لا يفتح بيانات الحساب السابق. signout cleanup cancellation يراعي subscriptions والـ pending deep link.

### 5.19 `[MODIFY] الملفات التوثيقية والإعدادات فقط عند التنفيذ

- `pubspec.yaml`/`pubspec.lock`: الحزم المذكورة فقط، دون version bump في مرحلة تطوير الأوفلاين.
- `android/app/src/main/AndroidManifest.xml`: ACCESS_NETWORK_STATE، backup rules للملفات الجديدة، لا تعديلات release signing.
- `[CREATE] android/app/src/main/res/xml/offline_backup_rules.xml` و`offline_data_extraction_rules.xml`: استبعاد database queue والجلسة من backup/transfer وفق min/targetSdk الحاليين. راجع ملف التخزين الفعلي قبل تحديد exclude path.
- `supabase/config.toml`: entry للـ dispatcher مع verify_jwt=false **فقط** لأنه يملك تحقق secret خادمي صريح؛ لا تعطيل JWT بوصفه بديلًا للمصادقة. RPCs خلف Supabase Auth تبقى محمية.
- `supabase/APP_UPDATES.md`: سياسة offline-cache الجديدة، بدون تغيير enforce flag في الإنتاج.
- لا تعدّل key.properties أو keystore أو applicationId أو google-services.json أو assets أو release version دون مهمة إصدار مستقلة.

## 6. سيناريوهات العمل وتسلسل النشر والفحص

### تسلسل إنشاء بيع أوفلاين

```text
Press Save
  -> validate fields / active cached employee grant
  -> allocate UUID once
  -> SQLite transaction: pending sale + offline action + episode
  -> commit succeeds
  -> show saved-on-device Arabic message + update employee total
  -> register constrained background work
  -> reconnect: coordinate session + check company/update policy
  -> reconcile uncertain online requests
  -> freeze original episode membership and N
  -> begin batch, stage ALL chunks, seal
  -> process pages idempotently with receipt + outbox in transaction
  -> apply server results locally
  -> finalize ONE summary after all outcomes become terminal
  -> backend dispatcher delivers allowed individual events + summary
  -> admin sees updated server rows and can open full report
```

### ترتيب التنفيذ الآمن

1. التقط hashes للملفات المستهدفة وschema catalog في بيئة اختبار؛ إذا اختلفت الملفات عن تاريخ الخطة راجع الفرق قبل استبدال أي شيء. لا تطبق تغييرات حرفية فوق تعديل أحدث غير مفهوم.
2. أضف schema/RPCs/outbox في Supabase اختبار أولًا، مع حماية metadata وتوافق القديم. شغّل SQL isolation/role tests قبل أي تطبيق تجريبي.
3. أضف shared Firebase module وdispatcher، ثم notify-sale bridge، ثم trigger الجديد. لا تترك القديم والجديد يرسلان مباشرة معًا.
4. فعّل cron/wake-up في الاختبار وتحقق عمليًا من أن إرسالًا failed ينتقل لإعادة محاولة دون duplicate logical event.
5. أضف store/models/tests؛ بعدها session adapter وqueue/repository؛ بعدها worker؛ ثم الشاشات والملاحة.
6. اختبر الدخول السابق والجديد والأوفلاين وتبديل الحسابات وسحب الصلاحيات والتحديث الإجباري قبل التجربة على حسابات تشغيل حقيقية.
7. لا تنشر هجرة الإنتاج/Edge Functions ولا ترسل إشعارات لمديري الإنتاج أو تنشئ مبيعات تجريبية حقيقية ضمن مجرد PLAN. أثناء IMPLEMENT تحقّق من تفويض نشر الإنتاج ونطاق fixtures قبل إجراء هذه الآثار.
8. قبل rollout احتفظ بالإصدار المتوافق للخادم مع APK القديم. rollback للتطبيق لا يحذف الجداول أو receipts أو pending queue. تعطيل worker مؤقتًا لا يمحو الطابور.

أوامر النشر التالية للمرحلة المصرح بها بعد اجتياز الاختبار، لا تنفذها أثناء PLAN:

```powershell
supabase functions deploy dispatch-sale-notifications --project-ref gjpqxsrsprenrhrenjxc --no-verify-jwt
supabase functions deploy notify-sale --project-ref gjpqxsrsprenrhrenjxc --no-verify-jwt
```

إعداد secret وVault وCron يعتمد أسماء القيم التي ستنشأ في بيئة الاختبار؛ لا تستخدم CHANGE_ME قيمة تشغيلية، ولا تطبع الأسرار في التقرير أو Git. لا تدّعِ تفعيل الجدولة لمجرد deploy function.

### ملفات الاختبار المطلوبة

| الملف | الثوابت التي يجب إثباتها |
| --- | --- |
| `[CREATE] test/offline_store_test.dart` | atomic enqueue/activity، استمرار البيانات بعد reopen، rollback عند full disk، فصل user/company، revision conflict، freeze immutable، lease two connections+expiry+fencing |
| `[CREATE] test/offline_sales_repository_test.dart` | pending يظهر فورًا، منع duplicate عند ACK loss، integer cents، merge remote/local بالUUID، cancelled/failed خارج الإجمالي، cache empty vs error، رفض نوع شركة أخرى |
| `[CREATE] test/offline_sync_service_test.dart` | chunks لا تغير N، retry نفس IDs، session refresh before RPC، foreground/worker race، session_epoch switch، partial rejection، no summary before complete، unknown error not permanent |
| `[CREATE] test/offline_cold_start_test.dart` | session+grant صالح اليوم التالي، بدون cache يمنع، grant expired يمنع، known company inactive يمنع، تحديث معروف قديم يمنع، سياسة cached تسمح فقط بشروطها |
| `[CREATE] test/offline_employee_ui_test.dart` | banner عربي وRTL320px، cached form، local success، no success on disk error، edit/cancel pending، no edit uncertain/frozen، manual sync spinner، older pending separate |
| `[CREATE] test/offline_report_navigation_test.dart` | cold notification tap→auth→authorized report، foreground/background الفرق، تبديل الحساب، forged company payload، loading/error/large report paging |
| `[CREATE] supabase/tests/offline_sales_sync_test.sql` | idempotency مع two transactions، role/company/type isolation، immutable receipts بعد حذف sale، canonical conflict، inactive company، min price/max input، created_at/synced_at |
| `[CREATE] supabase/tests/offline_notification_policy_test.sql` | N=0/1/3/10/11، النجاح الجزئي، UNIQUE summary، chunk boundaries، لا legacy duplicate، report RLS، metadata forgery denied |
| `[CREATE] supabase/functions/dispatch-sale-notifications/index_test.ts` | mock OAuth/FCM، per-token retry، 429/5xx، permanent invalid token، lease expiry، payload UTF-8 cap، unique Android tags، active recipients only |
| existing test files | كل الاختبارات الحالية تبقى ناجحة؛ تعديل توقعات startup update failure فقط بما يعكس سياسة cache الجديدة صراحة |

### الاختبار اليدوي المصرح به على الهاتف

استخدم حساب موظف ومدير **لشركة اختبار**، وليس بيانات مالية حقيقية. لا تفترض وجود هاتف متصل؛ تحقق بـ adb devices. تغيير Wi-Fi/mobile data أو force-stop يكون على جهاز الاختبار المصرح به، وأعد إعداداته بعد الانتهاء.

1. Online: login، cache profile/policy/types، أضف بيعًا؛ receipt واحدة وpush المعتاد مرة واحدة؛ الصورة fallback لا تمنع الإضافة.
2. Offline: اقطع Wi-Fi/data، أضف3؛ تظهر فورًا pending، يزداد count/total بقيم القروش الصحيحة؛ تعديل واحدة وتسجيل before/after، أنشئ رابعة ثم ألغها ولا تحتسبها كمبيعات.
3. Cold start: force-stop ثم افتح يدويًا بدون الإنترنت؛ ملف الموظف والقائمة والform تعمل، الصفوف لا تضيع ولا تتحول لشركة أخرى. **لا تتوقع background execution أثناء force-stop قبل الفتح.**
4. Reconnect: لا تضغط manual sync؛ يلتقط المراقب الشبكة ويبدأ؛ يتحول3 إلى synced بعد server ACK، بلا duplicate sales؛ المدير يستقبل3 فردية+ملخص واحد يشمل التعديل والإلغاء.
5. كرر دفعات1،10،11، ودفعة11 تُرفع50/أو chunks أصغر للاختبار؛ العدد2،11،1 على التوالي؛ لا11 individual عند صفحة أقل من10 داخل batch كبيرة.
6. Partial failure: دفعة11 بها6 أنواع غير مسموحة في بيئة الاختبار؛ يثبت5 accepted/6 rejected ويصل ملخص واحد فقط. اختبر جميعها مرفوضة وcancel-only.
7. Robustness: قطع الاتصال بعد commit قبل ACK، worker/foreground معًا، kill أثناء staging وبعد حفظ sale وقبل تطبيق ACK، محاولات أخرى للدفعة نفسها؛ لا resurrection ولا duplicate logical notification.
8. Auth/security: انتهاء token خلال ساعتين offline؛ refresh ناجح ثم upload؛ revoked token يحتاج دخولًا ولا يمسح queue؛ تعطيل الشركة يمنع الكتابة والإرسال؛ userB لا يرى أو يرفع queueA؛ إعادة تفعيل/دخولA يعالجها وفق قرار الخادم.
9. Dates: طلب11:59م وطلب12:01ص؛ وصول كلاهما غدًا؛ created_at الحقيقي يحدد اليوم، المدير يجد المتأخر في السابقة؛ pending أمس لا تختفي من قسم المتابعة. اختبر DST والساعة المتقدمة، واعرض audit difference.
10. Push: تحقق جهاز مدير منفصل foreground/background، permission denied/no token، notification tap بعد kill/login، نص عربي طويل، تقرير أكبر من FCM cap، token ثاني فاشل بعد نجاح الأول. سجّل «قبلته Firebase» منفصلًا عن «ظهر على الجهاز».
11. Update: cache سياسة مسموحة+offline grant→يفتح؛ cache requiresUpdate→يظل مغلقًا؛ cache absent/expired→retry؛ reconnect policy جديدة تحظر قبل رفع؛ pending لا تمسح.
12. Legacy APK: old INSERT ما زال يعمل ويصدر online event واحدًا، معرفات bigint وروابط previous sales والحذف محفوظة. لا يطالب بإرسال UUID من APK لا يعرفه.

### أوامر الفحص أثناء IMPLEMENT

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
deno test supabase/functions/dispatch-sale-notifications
```

SQL tests على قاعدة اختبار فقط داخل transaction/rollback؛ race tests تستخدم اتصالين ومراقبة النتائج. لا تستخدم أوامر حذف تنظيف واسعة أو تعطيل RLS لتسهيل نجاح الاختبارات.

إذا أظهر البناء خطأ، أصلح السبب الفعلي وأعد الفحوص المتأثرة. إذا تكرر نفس الفشل ثلاث محاولات بلا تقدم أو احتاج credentials/device/permission غير متاحة، سجّل العائق بدقة ولا تتوسع في تغييرات غير مرتبطة ولا تدّعِ نسبة100%.

### قائمة التحقق النهائية

#### PLAN — مكتمل في هذه المرحلة

- [x] قراءة المهارة المثبتة وقواعد الإشعارات1..10/>10 والملخص الدائم.
- [x] فحص مسارات البيع والأنواع والملف الشخصي والـ auth gate وforce-update والتوقيع والـ notification trigger/Edge Function/RLS المحلية.
- [x] تحديد تعارض offline cold-start مع force-update الحالي ومع معرفات bigint وخطة حل غير هدّام.
- [x] تحديد عقود التخزين والدفعات والصلاحيات والإرسال والـ tests وأوامر التنفيذ.
- [x] عدم تنفيذ migrations/deploy/build أو تعديل كود التطبيق أثناء PLAN.

#### IMPLEMENT — لا تُعلّم مكتملة قبل الإثبات

- [x] package additions/lockfile فقط دون ترقيات عامة؛ crypto/http أصبحا اعتمادين مباشرين لسلامة البروتوكول وتنسيق refresh.
- [x] LocalSale وOfflineSyncBatch وOfflineStore مكتملة بلا placeholders.
- [x] OfflineSessionService وstorage adapter وepoch/lease عبر isolates، بما في ذلك التجديد الضمني في SDK.
- [x] OfflineSalesRepository وOfflineSyncService والـ background dispatcher، مع cursors دائمة لاستكمال نقل وقراءة الدفعات الكبيرة.
- [x] offline_sales_sync.sql وكل RPCs/guards/indexes/RLS والـ legacy bridge.
- [x] shared Firebase module وoutbox dispatcher وCron/Vault مع تحقق auth.
- [x] per-device delivery tracking وbounded retry وUTF-8 payload limit؛ اختبار جهاز ناجح وآخر فاشل لا يعيد إرسال الناجح.
- [x] main/auth/update/type/sales/add-sale/home integrations.
- [x] status UI وreports screen وadmin inbox وnotification deep links؛ تأكيد التشغيل على هاتف فعلي ما زال أدناه غير مكتمل.
- [x] Android permission/backup exclusions دون تغيير الحزمة/المفاتيح.
- [x] unit/widget/SQL/Edge tests الجديدة والقديمة: 85 Flutter و6 Deno واختبارات PostgreSQL المعزولة.
- [x] flutter pub get / flutter analyze / flutter test / debug build ناجحة.
- [x] اختبارات1/3/10/11 وpartial failure وcancel-only منع duplication موثقة في قاعدة الاختبار المحلية.
- [x] cold-start/session expiration/suspension/account switch/update-policy verified بالاختبارات الآلية؛ التحقق اليدوي منفصل.
- [ ] جهاز الموظف والمدير: دليل ظهور الإشعارات وليس قبول Firebase فقط.
- [x] مراجعة git diff النهائية وdiff --check؛ لا credentials جديدة ولا production fixtures ولا تغيير بيانات سجاد أو signing في هذه المهمة. تغييرات المهام السابقة الموجودة بالـ worktree محفوظة.
- [x] نشر الإنتاج بعد تفويض صريح واختبار PostgreSQL محلي معزول، مع الحفاظ على مسار legacy INSERT. لم تُنشأ مبيعات اختبار بالإنتاج.

### ما لم يتم التحقق منه أثناء PLAN

لم يُشغل كود أوفلاين لأنه لم يُكتب في التطبيق بعد، ولم تُختبر schema حية أو أجهزة أو تلقي push لهذه الميزة. التصميم أعلاه مواصفة تنفيذ مرتبطة بالكود الحالي، وليس تطبيقًا تم تجميعه أو هجرة قابلة للنشر منفردة. عند IMPLEMENT يجب كتابة الملفات كاملة، ومراجعة API الحزم المحلولة ومخطط قاعدة الاختبار قبل التنفيذ، ثم تسجيل الأدلة الفعلية بدل تحويل جميع مربعات الاختبار إلى مكتملة تلقائيًا.

## سجل IMPLEMENT — 2026-11-02

الفقرة السابقة توثق حالة نهاية PLAN تاريخيًا؛ الحالة الحالية كما يلي:

- التطبيق يحفظ مبيعات الموظف وسجل التعديل/الإلغاء في SQLite، ويحافظ على UUID العملية ومعرّف السيرفر bigint منفصلين. النسخ الأونلاين الجديدة تستخدم UUID أيضًا، ويعيد نموذج الإضافة نفس UUID ووقت الإنشاء عند إعادة المحاولة.
- التخزين الفعلي يستخدم جدول cache واحدًا بمفاتيح user/company بدل تكرار جداول cache منفصلة، مع جداول queue/activity/batches/leases. هذا لا يغير عزل البيانات أو مصدر الحقيقة المالي.
- خدمة الجلسة تستعمل SharedPreferencesAsync مع ترحيل المفتاح السابق. Supabase يبدأ بـ EmptyLocalStorage لكي لا يمحو استرجاع الجلسة الافتراضي جلسة منتهية أثناء انقطاع الإنترنت. CoordinatedAuthClient ينسق حتى refresh الضمني داخل getSession، ويمنع الرد القديم من الكتابة بعد تغيير epoch.
- المزامنة تستأنف manifest مثبتة ومواضع نقل ونتائج محفوظة بعد إعادة التشغيل. أخطاء الشبكة لا تعيد إنشاء البيع أو تغير عتبة الإشعارات. نشاط الإلغاء بدون أي بيع باقٍ يبقى مستحقًا لملخص.
- السيرفر يستخدم receipts وoutbox وdelivery ledger. الهدف أجهزة المديرين النشطين بالشركة، لا topic عمومي. التحديث الفوري pg_net تحسين، وCron كل دقيقة يستعيد العمل عند فشله.
- أضيف register_current_device لنقل ملكية token نفسه عند تبديل الحساب على الجهاز، بعد التحقق من المستخدم والشركة على الخادم.
- تظهر أنواع المركبات والأسعار من cache، وتُحمّل مسبقًا عند التحقق من دخول الموظف أونلاين. الطلبات المتزامنة لا تصبح قابلة للتعديل أو الحذف أوفلاين.
- تقرير المزامنة يحتوي الموظف والفترة والطلبات والنتائج وسجل النشاط؛ الشركة الأخرى لا تستطيع قراءته. بيانات الصور والسجاد بقيت خارج نطاق الأوفلاين.

### أدلة التحقق

| الفحص | النتيجة |
| --- | --- |
| flutter pub get / flutter analyze | ناجح؛ لا أخطاء أو تحذيرات تحليل |
| flutter test | 85 اختبارًا ناجحًا |
| Deno check/test | نجح فحص الأنواع و6 اختبارات باستخدام Firebase/HTTP وهميين؛ لا رسالة تجريبية أُرسلت |
| PostgreSQL isolated fixtures | الهجرة والعزل والعتبة والرفض الجزئي وcancel-only وreceipt بعد حذف البيع وmetadata forgery وملكية token والـ delivery lease نجحت؛ rollback للبيانات |
| اتصالا PostgreSQL متزامنان | عملية واحدة + receipt واحدة + outbox event واحد لنفس UUID؛ fixtures نُظفت محليًا |
| debug Android APK | نجح؛ المسار `build/app/outputs/flutter-apk/app-debug.apk` |
| Supabase deployment | SQL والدالتان notify-sale وdispatch-sale-notifications نُشرت؛ secret عشوائي محفوظ في Edge/Vault دون نسخه في الكود |
| Supabase status | 6 جداول مع RLS، cron job واحد نشط وآخر تشغيل succeeded، sales ضمن Realtime، anonymous sale RPC ممنوع وclient claim ممنوع |
| Dispatcher HTTP | استجابة `{ok:true,processed:0}`؛ لم يُنشئ الفحص مبيعات أو أحداثًا وهمية بالإنتاج |
| أجهزة فعلية | adb devices خالٍ؛ لا ادعاء باختبار استقبال المدير على هاتف أو background scheduling فعليًا |

لا تحتاج تشغيل SQL إضافي للمشروع المرتبط. إصدار المتجر لم يُبنَ في هذه المرحلة، ورقم التطبيق بقي `1.0.9+11` كما طلبت الخطة. ملفات release APK/AAB القديمة لا تتضمن هذا التنفيذ؛ APK الناتج هنا debug للاختبار، وليس ملف Google Play جديدًا.

### المتبقي في TEST

تحديث اختبار الهاتف بتاريخ 2026-11-02: اتصل Samsung SM-S938B عبر Wireless ADB. ظهر خطأ `SqfliteDatabaseException: database_closed` بسبب مشاركة اتصال sqflite الافتراضي بين الشاشة وعامل Workmanager؛ عُولج باستخدام `singleInstance: false` لاتصال مستقل لكل محرك Flutter. أضيف اختبار انحدار يؤكد بقاء اتصال الشاشة والعمليات والأقفال سليمة بعد إغلاق اتصال العامل. نجحت 86 اختبارات Flutter والتحليل وبناء APK debug arm64، وثُبت التحديث باستخدام `adb install --no-streaming -r` دون مسح البيانات. تحقق بصريًا من شاشة المبيعات بلا خطأ، ومن تحميل ستة أنواع وصورها في إضافة المركبة واختيار جامبو وتعبئة السعر 200. لم تُحفظ أي مبيعات تجريبية؛ اختبار الخروج والإشعارات وسيناريوهات الأوفلاين الكاملة على الأجهزة لا يزال غير مكتمل. ملاحظات عدم اتصال الهاتف في سجل IMPLEMENT أعلاه تصف الحالة السابقة فقط.

- توصيل جهاز الموظف وجهاز المدير/حساب اختبار مصرح به، ثم السيناريوهات اليدوية أعلاه.
- الدخول أونلاين مرة قبل الاختبار حتى تُحفظ الجلسة وprofile والسياسة والأنواع. grant الأوفلاين صالح حتى7 أيام فقط، وإيقاف الحساب المعروف أو تحديث إلزامي معروف لا يمكن تجاوزه بالأوفلاين.
- إثبات ظهور 3 إشعارات فردية + ملخص واحد، و11 طلبًا بملخص واحد، على هاتف المدير؛ قبول Firebase أو نجاح cron وحده لا يثبت العرض.
- اختبار foreground/background وعودة الاتصال بعد swipe-away؛ force-stop يحتاج إعادة فتح التطبيق وفق قيود Android.
- قبل إصدار Play جديد، تحقق من أعلى versionCode المرفوع، وزد الرقم في مهمة إصدار منفصلة مع الحفاظ على signing key الحالية.
