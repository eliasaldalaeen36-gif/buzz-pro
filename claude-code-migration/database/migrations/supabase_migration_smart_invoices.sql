-- ============================================================
-- BUZZ Pro — الفواتير الذكية: تخزين الأصناف الفردية المستخرَجة من كل فاتورة
-- آمن تمامًا للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة.
-- انسخ هذا الملف كاملًا والصقه في SQL Editor بSupabase واضغط Run
-- ============================================================

create table if not exists invoice_line_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  expense_id uuid references expenses(id) on delete cascade,
  item_name text not null,
  quantity numeric default 1,
  unit_price numeric default 0,
  line_total numeric default 0,
  invoice_date date,
  vendor text default '',
  created_at timestamptz not null default now()
);

create index if not exists idx_invoice_line_items_business_item on invoice_line_items(business_id, item_name);
create index if not exists idx_invoice_line_items_expense on invoice_line_items(expense_id);

alter table invoice_line_items enable row level security;

drop policy if exists "business reads own line items" on invoice_line_items;
create policy "business reads own line items" on invoice_line_items
  for select using (business_id = public.my_business_id());

drop policy if exists "owner manages line items" on invoice_line_items;
create policy "owner manages line items" on invoice_line_items
  for all
  using (business_id = public.my_business_id() and public.is_owner())
  with check (business_id = public.my_business_id() and public.is_owner());

create or replace function public.set_invoice_line_item_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_business_trigger on invoice_line_items;
create trigger set_business_trigger before insert on invoice_line_items for each row execute function public.set_invoice_line_item_business();

NOTIFY pgrst, 'reload schema';
