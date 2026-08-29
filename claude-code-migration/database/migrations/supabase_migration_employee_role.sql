-- ============================================================
-- BUZZ Pro — حساب موظف مقيّد (إغلاقات يومية)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

-- جدول الأدوار: يربط كل مستخدم بدوره (مالك أو موظف)
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'employee' check (role in ('owner','employee')),
  display_name text default '',
  email text default '',
  created_at timestamptz default now()
);
alter table profiles enable row level security;

drop policy if exists "read own profile" on profiles;
create policy "read own profile" on profiles for select using (auth.uid() = id);

-- عند إنشاء أي مستخدم جديد: أول مستخدم يصبح "مالك" تلقائيًا، وأي مستخدم لاحق (ينشئه المالك لموظفيه) يصبح "موظف"
create or replace function public.handle_new_user()
returns trigger as $$
declare
  existing_count int;
begin
  select count(*) into existing_count from public.profiles;
  insert into public.profiles (id, role, email)
  values (new.id, case when existing_count = 0 then 'owner' else 'employee' end, new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- تعويض للحسابات الموجودة مسبقًا قبل تفعيل هذه الميزة (لم يُطلق عليها الـ trigger لأنها أُنشئت قبله)
-- كل حساب موجود بدون صفّ بجدول الأدوار يُسجَّل تلقائيًا كـ"مالك" (لأنه كان الحساب المشترك الوحيد قبل وجود مفهوم الموظف)
insert into public.profiles (id, role, email)
select u.id, 'owner', u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
on conflict (id) do nothing;

-- دالة مساعدة: هل المستخدم الحالي "مالك"؟
create or replace function public.is_owner()
returns boolean as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner');
$$ language sql security definer stable;

-- ============================================================
-- تحديث الصلاحيات: المالك يرى كل شيء، الموظف يقتصر على إدخالات اليوم فقط
-- في الإيرادات والمصاريف وحركة الأموال، وإتاحة كاملة لسجلّ الجرد (تسكير الكاش)
-- ============================================================

drop policy if exists "authenticated full access" on revenue;
drop policy if exists "owner full access" on revenue;
drop policy if exists "employee today only" on revenue;
create policy "owner full access" on revenue for all using (public.is_owner()) with check (public.is_owner());
create policy "employee today only" on revenue for all
  using (not public.is_owner() and date = current_date)
  with check (not public.is_owner() and date = current_date);

drop policy if exists "authenticated full access" on expenses;
drop policy if exists "owner full access" on expenses;
drop policy if exists "employee today only" on expenses;
create policy "owner full access" on expenses for all using (public.is_owner()) with check (public.is_owner());
create policy "employee today only" on expenses for all
  using (not public.is_owner() and date = current_date)
  with check (not public.is_owner() and date = current_date);

drop policy if exists "authenticated full access" on movements;
drop policy if exists "owner full access" on movements;
drop policy if exists "employee today only" on movements;
create policy "owner full access" on movements for all using (public.is_owner()) with check (public.is_owner());
create policy "employee today only" on movements for all
  using (not public.is_owner() and date = current_date)
  with check (not public.is_owner() and date = current_date);

drop policy if exists "authenticated full access" on cash_counts;
drop policy if exists "owner full access" on cash_counts;
drop policy if exists "employee full access" on cash_counts;
create policy "owner full access" on cash_counts for all using (public.is_owner()) with check (public.is_owner());
create policy "employee full access" on cash_counts for all using (not public.is_owner()) with check (not public.is_owner());

-- الجداول التالية للمالك فقط — الموظف لا يرى أو يعدّل عليها إطلاقًا
drop policy if exists "authenticated full access" on fixed_costs;
drop policy if exists "owner only" on fixed_costs;
create policy "owner only" on fixed_costs for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "authenticated full access" on debtors;
drop policy if exists "owner only" on debtors;
create policy "owner only" on debtors for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "authenticated full access" on creditors;
drop policy if exists "owner only" on creditors;
create policy "owner only" on creditors for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "authenticated full access" on bank_statement_lines;
drop policy if exists "owner only" on bank_statement_lines;
create policy "owner only" on bank_statement_lines for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "authenticated full access" on settings;
drop policy if exists "owner only" on settings;
create policy "owner only" on settings for all using (public.is_owner()) with check (public.is_owner());
