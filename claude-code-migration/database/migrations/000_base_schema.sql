-- ============================================================
-- BUZZ Pro — قاعدة بيانات مشتركة على Supabase
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

-- جدول الإعدادات (صف واحد فقط)
create table if not exists settings (
  id int primary key default 1,
  opening_cash numeric default 0,
  opening_bank numeric default 0,
  var_cost_pct numeric default 0.35,
  expense_threshold numeric default 0.70,
  due_alert_days int default 3,
  year int default extract(year from now()),
  constraint single_row check (id = 1)
);
insert into settings (id) values (1) on conflict (id) do nothing;

-- الإيرادات
create table if not exists revenue (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  amount numeric not null,
  method text not null,
  notes text default '',
  created_at timestamptz default now()
);

-- المصاريف
create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  amount numeric,
  category text,
  method text,
  notes text default '',
  created_at timestamptz default now()
);

-- التكاليف الثابتة
create table if not exists fixed_costs (
  id uuid primary key default gen_random_uuid(),
  name text default '',
  monthly_amount numeric default 0,
  due_date date,
  paid boolean default false,
  created_at timestamptz default now()
);

-- حركة الأموال
create table if not exists movements (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  type text not null,
  amount numeric not null,
  notes text default '',
  created_at timestamptz default now()
);

-- الذمم المدينة (عملاء)
create table if not exists debtors (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  party text default '',
  description text default '',
  amount numeric not null,
  settled boolean default false,
  settled_date date,
  created_at timestamptz default now()
);

-- الذمم الدائنة (موردون)
create table if not exists creditors (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  party text default '',
  description text default '',
  amount numeric not null,
  settled boolean default false,
  settled_date date,
  created_at timestamptz default now()
);

-- سجلّ الفروقات (الجرد)
create table if not exists cash_counts (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  place text not null,
  actual numeric not null,
  notes text default '',
  created_at timestamptz default now()
);

-- ============================================================
-- تفعيل الحماية (RLS): يُسمح فقط لمن سجّل دخول فعليًا بالقراءة/الكتابة
-- ============================================================
alter table settings enable row level security;
alter table revenue enable row level security;
alter table expenses enable row level security;
alter table fixed_costs enable row level security;
alter table movements enable row level security;
alter table debtors enable row level security;
alter table creditors enable row level security;
alter table cash_counts enable row level security;

drop policy if exists "authenticated full access" on settings;
create policy "authenticated full access" on settings for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on revenue;
create policy "authenticated full access" on revenue for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on expenses;
create policy "authenticated full access" on expenses for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on fixed_costs;
create policy "authenticated full access" on fixed_costs for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on movements;
create policy "authenticated full access" on movements for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on debtors;
create policy "authenticated full access" on debtors for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on creditors;
create policy "authenticated full access" on creditors for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists "authenticated full access" on cash_counts;
create policy "authenticated full access" on cash_counts for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
