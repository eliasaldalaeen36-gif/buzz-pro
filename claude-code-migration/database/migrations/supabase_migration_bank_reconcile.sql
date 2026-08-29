-- ============================================================
-- BUZZ Pro — تحديث قاعدة البيانات (تسوية البنك / المطابقة البنكية)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

create table if not exists bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  description text default '',
  amount numeric not null,
  direction text not null,          -- 'in' (قيد/إيداع) أو 'out' (سحب/خصم)
  matched_source text,              -- 'revenue' | 'expenses' | 'movements' أو فارغ إن لم تُطابَق بعد
  matched_id uuid,
  created_at timestamptz default now()
);

alter table bank_statement_lines enable row level security;

drop policy if exists "authenticated full access" on bank_statement_lines;
create policy "authenticated full access" on bank_statement_lines
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
