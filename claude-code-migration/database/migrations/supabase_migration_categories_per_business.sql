-- ============================================================
-- BUZZ Pro — موظف "حضور فقط" + فئات مصاريف مخصّصة لكل محل
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "التحويل لمنصة متعددة العملاء" أولًا
-- ============================================================

-- ============================================================
-- ١) نطاق صلاحية الموظف: إغلاق يومي كامل، أو حضور فقط بلا صلاحية الإغلاق
-- ============================================================
alter table profiles add column if not exists access_scope text not null default 'full';
alter table profiles drop constraint if exists profiles_access_scope_check;
alter table profiles add constraint profiles_access_scope_check check (access_scope in ('full','attendance_only'));

-- ============================================================
-- ٢) فئات وتصنيفات فرعية للمصاريف — مخصّصة لكل محل بدل قائمة موحّدة ثابتة
-- ============================================================
create table if not exists expense_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  name text not null,
  is_variable boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz default now()
);
alter table expense_categories enable row level security;

create table if not exists expense_subcategories (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references expense_categories(id) on delete cascade,
  business_id uuid references businesses(id),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz default now()
);
alter table expense_subcategories enable row level security;

drop policy if exists "read own business categories" on expense_categories;
create policy "read own business categories" on expense_categories for select using (business_id = public.my_business_id());
drop policy if exists "owner manages categories" on expense_categories;
create policy "owner manages categories" on expense_categories for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "read own business subcategories" on expense_subcategories;
create policy "read own business subcategories" on expense_subcategories for select using (business_id = public.my_business_id());
drop policy if exists "owner manages subcategories" on expense_subcategories;
create policy "owner manages subcategories" on expense_subcategories for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

-- ============================================================
-- ٣) دالة تبذر فئات المصاريف الافتراضية (نفس فئات BUZZ الأصلية) لأي محل
-- ============================================================
create or replace function public.seed_default_categories(target_business_id uuid)
returns void as $$
declare
  cat_id uuid;
begin
  if exists (select 1 from expense_categories where business_id = target_business_id) then
    return; -- لا تكرّر البذر لو كان المحل له فئات مسبقًا
  end if;

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'إيجار', false, 1) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'إيجار المحل', 1), (cat_id, target_business_id, 'إيجار معدات إضافية', 2);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'رواتب', false, 2) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'رواتب أساسية', 1), (cat_id, target_business_id, 'بدلات وحوافز', 2),
    (cat_id, target_business_id, 'سلف الموظفين', 3), (cat_id, target_business_id, 'مكافآت ومنح', 4), (cat_id, target_business_id, 'تأمينات', 5);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'مواد قهوة', true, 3) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'بن', 1), (cat_id, target_business_id, 'حليب', 2), (cat_id, target_business_id, 'سكر', 3),
    (cat_id, target_business_id, 'شراب ونكهات', 4), (cat_id, target_business_id, 'شاي', 5), (cat_id, target_business_id, 'ماتشا', 6),
    (cat_id, target_business_id, 'شوكولاتة', 7), (cat_id, target_business_id, 'مثلجات وآيس', 8),
    (cat_id, target_business_id, 'مكونات مشروبات باردة', 9), (cat_id, target_business_id, 'مواد حلويات ومخبوزات', 10);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'مرافق', false, 4) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'كهرباء', 1), (cat_id, target_business_id, 'ماء', 2), (cat_id, target_business_id, 'إنترنت واتصالات', 3), (cat_id, target_business_id, 'غاز', 4);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'صيانة', false, 5) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'معدات', 1), (cat_id, target_business_id, 'تكييف وتبريد', 2), (cat_id, target_business_id, 'سباكة وكهرباء عامة', 3), (cat_id, target_business_id, 'تجديد وديكور', 4);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'تسويق', false, 6) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'إعلانات سوشال ميديا', 1), (cat_id, target_business_id, 'طباعة', 2), (cat_id, target_business_id, 'عروض وخصومات', 3), (cat_id, target_business_id, 'تصوير ومحتوى', 4);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'تغليف', true, 7) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'أكواب', 1), (cat_id, target_business_id, 'أغطية', 2), (cat_id, target_business_id, 'شاليمو', 3),
    (cat_id, target_business_id, 'أكياس', 4), (cat_id, target_business_id, 'مناديل', 5), (cat_id, target_business_id, 'عصي تحريك', 6), (cat_id, target_business_id, 'علب حلويات', 7);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'نقل', false, 8) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'وقود', 1), (cat_id, target_business_id, 'صيانة مركبة التوصيل', 2), (cat_id, target_business_id, 'أجرة توصيل خارجي', 3);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'رسوم ورخص', false, 9) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'رسوم حكومية', 1), (cat_id, target_business_id, 'رخص تجارية', 2), (cat_id, target_business_id, 'تأمين المحل', 3), (cat_id, target_business_id, 'ضرائب', 4);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'عمولة توصيل', false, 10) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'طلبات', 1), (cat_id, target_business_id, 'منصات أخرى', 2), (cat_id, target_business_id, 'توصيل خاص', 3);

  insert into expense_categories (business_id, name, is_variable, sort_order) values (target_business_id, 'أخرى', false, 11) returning id into cat_id;
  insert into expense_subcategories (category_id, business_id, name, sort_order) values
    (cat_id, target_business_id, 'ضيافة الموظفين', 1), (cat_id, target_business_id, 'قرطاسية ولوازم مكتب', 2),
    (cat_id, target_business_id, 'اشتراكات', 3), (cat_id, target_business_id, 'أتعاب محاسب/محامٍ', 4), (cat_id, target_business_id, 'غير مصنّف', 5);
end;
$$ language plpgsql security definer;

grant execute on function public.seed_default_categories(uuid) to authenticated;

-- تحديث create_business لتبذر الفئات الافتراضية تلقائيًا لأي محل جديد من الآن فصاعدًا
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
  perform public.seed_default_categories(new_business_id);
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  values (auth.uid(), 'create_business', new_business_id, business_name, '');
  return new_business_id;
end;
$$ language plpgsql security definer;

-- بذر الفئات الافتراضية لأي محل موجود حاليًا وليس له فئات بعد (يشمل محلك الحالي)
do $$
declare
  biz record;
begin
  for biz in select id from businesses loop
    perform public.seed_default_categories(biz.id);
  end loop;
end $$;

-- دالة آمنة: المالك يحدّد نطاق صلاحية أحد موظفيه (إغلاق كامل أو حضور فقط)
create or replace function public.set_employee_access_scope(employee_user_id uuid, scope text)
returns void as $$
begin
  if scope not in ('full','attendance_only') then
    raise exception 'قيمة غير صحيحة للنطاق';
  end if;
  if not exists (
    select 1 from profiles me join profiles emp on emp.business_id = me.business_id
    where me.id = auth.uid() and me.role = 'owner' and emp.id = employee_user_id and emp.role = 'employee'
  ) then
    raise exception 'صلاحية مرفوضة: يمكنك فقط تعديل موظفي محلك';
  end if;
  update profiles set access_scope = scope where id = employee_user_id;
end;
$$ language plpgsql security definer;

grant execute on function public.set_employee_access_scope(uuid, text) to authenticated;
