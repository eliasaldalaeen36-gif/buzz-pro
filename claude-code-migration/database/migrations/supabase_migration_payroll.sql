-- ============================================================
-- BUZZ Pro — الرواتب والسلف
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

-- الموظفون ورواتبهم الشهرية
create table if not exists staff (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  monthly_salary numeric not null default 0,
  active boolean not null default true,
  notes text default '',
  created_at timestamptz default now()
);

-- سجلّ السلف ودفعات الرواتب لكل موظف
create table if not exists salary_transactions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references staff(id) on delete cascade,
  date date not null,
  type text not null check (type in ('advance','payment')),
  amount numeric not null,
  notes text default '',
  created_at timestamptz default now()
);

alter table staff enable row level security;
alter table salary_transactions enable row level security;

-- بيانات الرواتب حساسة — للمالك فقط (نفس مستوى حماية الديون والتكاليف الثابتة)
drop policy if exists "owner only" on staff;
create policy "owner only" on staff for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "owner only" on salary_transactions;
create policy "owner only" on salary_transactions for all using (public.is_owner()) with check (public.is_owner());
