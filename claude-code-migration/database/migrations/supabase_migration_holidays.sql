-- ============================================================
-- BUZZ Pro — تحديد أيام عطلة يدوية لكل موظف (تحكّم كامل بيدك)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "ربط الموظف بحساب الدخول" أولًا
-- ============================================================

create table if not exists employee_holidays (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  staff_id uuid references staff(id) on delete cascade,
  holiday_date date not null,
  created_at timestamptz default now(),
  unique (staff_id, holiday_date)
);
alter table employee_holidays enable row level security;

drop policy if exists "owner manages holidays" on employee_holidays;
create policy "owner manages holidays" on employee_holidays for all using (business_id = public.my_business_id() and public.is_owner()) with check (business_id = public.my_business_id() and public.is_owner());

create or replace function public.set_holiday_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_business_trigger on employee_holidays;
create trigger set_business_trigger before insert on employee_holidays for each row execute function public.set_holiday_business();
