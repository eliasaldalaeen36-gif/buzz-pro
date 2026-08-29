-- ============================================================
-- BUZZ Pro — نوع الإجازة (مدفوعة/غير مدفوعة) + تعديل يدوي لساعات الحضور
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية supabase_migration_holidays.sql أولًا (لجدول employee_holidays)
-- ============================================================

-- ١) نوع الإجازة: كل الإجازات الحالية تُعتبَر "مدفوعة" تلقائيًا (نفس السلوك المعمول به سابقًا) —
--    لا تغيير على أي حساب راتب موجود بأثر رجعي.
alter table employee_holidays add column if not exists leave_type text not null default 'paid';
alter table employee_holidays drop constraint if exists employee_holidays_leave_type_check;
alter table employee_holidays add constraint employee_holidays_leave_type_check check (leave_type in ('paid', 'unpaid'));

-- ٢) تعديل يدوي لساعات حضور يوم معيّن — يتجاوز الحساب التلقائي من البصمة لذلك اليوم تحديدًا
--    (لحالات مثل: نسي الموظف يبصم، تأخّر النظام، مشكلة تقنية بجهاز البصمة).
create table if not exists attendance_overrides (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  staff_id uuid references staff(id) on delete cascade,
  work_date date not null,
  hours numeric not null check (hours >= 0 and hours <= 24),
  note text default '',
  created_at timestamptz not null default now(),
  unique (staff_id, work_date)
);

create index if not exists idx_attendance_overrides_staff on attendance_overrides(staff_id, work_date);

alter table attendance_overrides enable row level security;

drop policy if exists "owner manages attendance overrides" on attendance_overrides;
create policy "owner manages attendance overrides" on attendance_overrides
  for all using (business_id = public.my_business_id() and public.is_owner())
  with check (business_id = public.my_business_id() and public.is_owner());

-- تعيين business_id تلقائيًا عند الإدخال، بنفس نمط جدول employee_holidays بالضبط
create or replace function public.set_attendance_override_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_business_trigger on attendance_overrides;
create trigger set_business_trigger before insert on attendance_overrides for each row execute function public.set_attendance_override_business();
