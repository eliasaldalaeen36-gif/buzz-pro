-- ============================================================
-- BUZZ Pro — التحويل لمنصة متعددة العملاء (Multi-Tenant SaaS)
-- ═══════════════════════════════════════════════════════════
-- ⚠️⚠️⚠️ تحذير حاسم: شغّل هذا الملف مرة واحدة فقط، اليوم، ثم لا تشغّله مرة
-- أخرى أبدًا مهما حصل — يحتوي أوامر حذف تمسح بيانات كل المحلات دفعة واحدة.
-- بعد اليوم، أي تحديث لاحق سيأتيك بملف مختلف تمامًا لا يحتوي أي حذف.
-- ═══════════════════════════════════════════════════════════
-- هذا الملف يبدأ من الصفر: يحذف كل البيانات الحالية بكل الجداول
-- (المصادقة على هذا مسبقًا من صاحب النظام — البيانات الحالية تجريبية)
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل كل الترقيات السابقة أولًا (حساب الموظف، الرواتب، سجلّ التدقيق)
-- ============================================================

-- ============================================================
-- ١) جدول المحلات (كل عميل/محل = صف واحد هنا)
-- ============================================================
create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text default '',
  active boolean not null default true,
  created_at timestamptz default now()
);
alter table businesses enable row level security;

-- ============================================================
-- ٢) جدول الأدوار: إضافة business_id + دور "مدير عام" جديد
-- ============================================================
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check check (role in ('super_admin','owner','employee','pending'));
alter table profiles add column if not exists business_id uuid references businesses(id);

-- ============================================================
-- ٣) حسابك الحالي (الأقدم) يصبح "مدير عام" تلقائيًا، وأي حساب آخر موجود
-- يُصفَّر لحالة "معلَّق" (بما إن كل الربط بمحلات القديمة صار بلا معنى بعد التصفير)
-- ============================================================
do $$
declare
  admin_id uuid;
begin
  select id into admin_id from profiles order by created_at asc limit 1;
  if admin_id is not null then
    update profiles set role = 'super_admin', business_id = null where id = admin_id;
    update profiles set role = 'pending', business_id = null where id <> admin_id;
  end if;
end $$;

-- ============================================================
-- ٤) تصفير كل بيانات الأعمال الحالية (بدء من الصفر كما تم تأكيده)
-- ============================================================
delete from revenue;
delete from expenses;
delete from fixed_costs;
delete from movements;
delete from debtors;
delete from creditors;
delete from cash_counts;
delete from bank_statement_lines;
delete from staff;
delete from salary_transactions;
delete from settings;

-- ============================================================
-- ٤) إعادة بناء جدول الإعدادات: صف واحد لكل محل بدل صف عام واحد للتطبيق كله
-- ============================================================
alter table settings drop constraint if exists single_row;
alter table settings alter column id drop default;
alter table settings alter column id type uuid using gen_random_uuid();
alter table settings alter column id set default gen_random_uuid();
alter table settings add column if not exists business_id uuid references businesses(id);
alter table settings drop constraint if exists settings_business_unique;
alter table settings add constraint settings_business_unique unique (business_id);

-- ============================================================
-- ٥) إضافة business_id لكل جداول البيانات
-- ============================================================
alter table revenue add column if not exists business_id uuid references businesses(id);
alter table expenses add column if not exists business_id uuid references businesses(id);
alter table fixed_costs add column if not exists business_id uuid references businesses(id);
alter table movements add column if not exists business_id uuid references businesses(id);
alter table debtors add column if not exists business_id uuid references businesses(id);
alter table creditors add column if not exists business_id uuid references businesses(id);
alter table cash_counts add column if not exists business_id uuid references businesses(id);
alter table bank_statement_lines add column if not exists business_id uuid references businesses(id);
alter table staff add column if not exists business_id uuid references businesses(id);
alter table salary_transactions add column if not exists business_id uuid references businesses(id);

-- ============================================================
-- ٦) دوال مساعدة للصلاحيات
-- ============================================================
create or replace function public.is_super_admin()
returns boolean as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'super_admin');
$$ language sql security definer stable;

create or replace function public.my_business_id()
returns uuid as $$
  select business_id from public.profiles where id = auth.uid();
$$ language sql security definer stable;

create or replace function public.is_employee()
returns boolean as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'employee');
$$ language sql security definer stable;

-- is_owner القديمة تبقى تعمل (تُستخدم لتمييز مالك عن موظف داخل نفس المحل)

-- ============================================================
-- ٧) إعادة تعريف تعبئة الأدوار عند إنشاء أي حساب جديد
-- أول حساب في كل قاعدة البيانات = مدير عام. أي حساب لاحق = "معلَّق" حتى يُسنَد صراحةً
-- (لا يُمنح أي وصول لأي محل تلقائيًا أبدًا بمجرد التسجيل)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger as $$
declare
  existing_count int;
begin
  select count(*) into existing_count from public.profiles;
  insert into public.profiles (id, role, email, business_id)
  values (new.id, case when existing_count = 0 then 'super_admin' else 'pending' end, new.email, null);
  return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- ٨) دوال آمنة لإسناد الأدوار — تتحقق من صلاحية المستدعي داخل الخادم نفسه
-- ============================================================

-- المدير العام فقط: إنشاء محل جديد وتعيين مالكه
create or replace function public.create_business(business_name text, business_type_in text, owner_user_id uuid)
returns uuid as $$
declare
  new_business_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  insert into businesses (name, business_type) values (business_name, business_type_in) returning id into new_business_id;
  update profiles set role = 'owner', business_id = new_business_id where id = owner_user_id;
  insert into settings (business_id) values (new_business_id);
  return new_business_id;
end;
$$ language plpgsql security definer;

-- المالك فقط: ربط حساب موظف جديد بمحله هو تحديدًا
create or replace function public.assign_employee_to_my_business(employee_user_id uuid)
returns void as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'owner') then
    raise exception 'صلاحية مرفوضة: هذا الإجراء لمالك المحل فقط';
  end if;
  update profiles set role = 'employee', business_id = (select business_id from profiles where id = auth.uid())
  where id = employee_user_id and role = 'pending';
end;
$$ language plpgsql security definer;

grant execute on function public.create_business(text, text, uuid) to authenticated;
grant execute on function public.assign_employee_to_my_business(uuid) to authenticated;

-- ============================================================
-- ٩) تعبئة business_id تلقائيًا عند إضافة أي صف جديد (بالإضافة لأعمدة التدقيق الموجودة)
-- ============================================================
create or replace function public.set_audit_fields()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    NEW.created_by = auth.uid();
    NEW.updated_by = auth.uid();
    NEW.updated_at = now();
    if NEW.business_id is null then
      NEW.business_id = public.my_business_id();
    end if;
  elsif TG_OP = 'UPDATE' then
    NEW.created_by = OLD.created_by;
    NEW.business_id = OLD.business_id; -- لا يمكن نقل صف لمحل آخر عبر تعديل
    NEW.updated_by = auth.uid();
    NEW.updated_at = now();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

-- ============================================================
-- ١٠) إعادة كتابة كل صلاحيات الحماية: فصل صارم بين المحلات + صلاحيات مالك/موظف كما كانت
-- ملاحظة مهمة: كل الفحوصات تستخدم دوالًا آمنة (security definer) فقط، ولا يوجد أي
-- استعلام مباشر على profiles بداخل سياسة على profiles نفسها — هذا يمنع "تكرارًا لا نهائيًا"
-- كان يحدث فعليًا عند الاختبار (اكتُشف وأُصلح بعد اختبار فعلي وليس افتراضًا)
-- ============================================================

-- الملفات الشخصية
drop policy if exists "read own profile" on profiles;
create policy "read own profile" on profiles for select using (auth.uid() = id);
drop policy if exists "owner reads all profiles" on profiles;
drop policy if exists "owner reads own business profiles" on profiles;
create policy "owner reads own business profiles" on profiles for select using (
  public.is_owner() and business_id = public.my_business_id()
);
drop policy if exists "super admin reads all profiles" on profiles;
create policy "super admin reads all profiles" on profiles for select using (public.is_super_admin());

-- المحلات: المدير العام فقط يديرها، وكل مستخدم يقرأ محله فقط (لعرض اسمه بالتطبيق)
drop policy if exists "super admin manages businesses" on businesses;
create policy "super admin manages businesses" on businesses for all using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "read own business" on businesses;
create policy "read own business" on businesses for select using (id = public.my_business_id());

-- الإعدادات: لكل محل صفّه فقط، والمالك يعدّل، والموظف يقرأ فقط
drop policy if exists "owner only" on settings;
drop policy if exists "settings read own business" on settings;
create policy "settings read own business" on settings for select using (business_id = public.my_business_id());
drop policy if exists "settings owner writes" on settings;
create policy "settings owner writes" on settings for all using (
  business_id = public.my_business_id() and public.is_owner()
) with check (
  business_id = public.my_business_id() and public.is_owner()
);

-- الإيرادات والمصاريف وحركة الأموال: مالك كامل + موظف يومه فقط، ضمن محله فقط
drop policy if exists "owner full access" on revenue; drop policy if exists "employee today only" on revenue;
drop policy if exists "biz owner full access" on revenue;
create policy "biz owner full access" on revenue for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());
drop policy if exists "biz employee today only" on revenue;
create policy "biz employee today only" on revenue for all using (business_id = public.my_business_id() and public.is_employee() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and date = current_date);

drop policy if exists "owner full access" on expenses; drop policy if exists "employee today only" on expenses;
drop policy if exists "biz owner full access" on expenses;
create policy "biz owner full access" on expenses for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());
drop policy if exists "biz employee today only" on expenses;
create policy "biz employee today only" on expenses for all using (business_id = public.my_business_id() and public.is_employee() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and date = current_date);

drop policy if exists "owner full access" on movements; drop policy if exists "employee today only" on movements;
drop policy if exists "biz owner full access" on movements;
create policy "biz owner full access" on movements for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());
drop policy if exists "biz employee today only" on movements;
create policy "biz employee today only" on movements for all using (business_id = public.my_business_id() and public.is_employee() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and date = current_date);

-- الجرد: مالك وموظف كليهما وصول كامل، ضمن محلهم فقط
drop policy if exists "owner full access" on cash_counts; drop policy if exists "employee full access" on cash_counts;
drop policy if exists "biz full access same business" on cash_counts;
create policy "biz full access same business" on cash_counts for all using (business_id = public.my_business_id()) with check (business_id = public.my_business_id());

-- باقي الجداول: للمالك فقط ضمن محله
drop policy if exists "owner only" on fixed_costs;
drop policy if exists "biz owner only" on fixed_costs;
create policy "biz owner only" on fixed_costs for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "owner only" on debtors;
drop policy if exists "biz owner only" on debtors;
create policy "biz owner only" on debtors for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "owner only" on creditors;
drop policy if exists "biz owner only" on creditors;
create policy "biz owner only" on creditors for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "owner only" on bank_statement_lines;
drop policy if exists "biz owner only" on bank_statement_lines;
create policy "biz owner only" on bank_statement_lines for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "owner only" on staff;
drop policy if exists "biz owner only" on staff;
create policy "biz owner only" on staff for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "owner only" on salary_transactions;
drop policy if exists "biz owner only" on salary_transactions;
create policy "biz owner only" on salary_transactions for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

-- سجلّ التدقيق: للمالك ضمن محله فقط (لا للمدير العام تلقائيًا — خصوصية بيانات العملاء)
drop view if exists audit_log;
create view audit_log with (security_invoker = true) as
select t.table_name, t.id, t.ref_date, t.amount, t.created_at, t.created_by, t.updated_at, t.updated_by, t.business_id,
       p1.email as created_by_email, p2.email as updated_by_email
from (
  select 'revenue' as table_name, id, date::text as ref_date, amount, created_at, created_by, updated_at, updated_by, business_id from revenue
  union all
  select 'expenses', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from expenses
  union all
  select 'movements', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from movements
  union all
  select 'debtors', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from debtors
  union all
  select 'creditors', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from creditors
  union all
  select 'cash_counts', id, date::text, actual, created_at, created_by, updated_at, updated_by, business_id from cash_counts
  union all
  select 'fixed_costs', id, null::text, monthly_amount, created_at, created_by, updated_at, updated_by, business_id from fixed_costs
  union all
  select 'staff', id, null::text, monthly_salary, created_at, created_by, updated_at, updated_by, business_id from staff
  union all
  select 'salary_transactions', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from salary_transactions
  union all
  select 'bank_statement_lines', id, date::text, amount, created_at, created_by, updated_at, updated_by, business_id from bank_statement_lines
) t
left join profiles p1 on p1.id = t.created_by
left join profiles p2 on p2.id = t.updated_by
where t.business_id = public.my_business_id()
  and public.is_owner();

grant select on audit_log to authenticated;
