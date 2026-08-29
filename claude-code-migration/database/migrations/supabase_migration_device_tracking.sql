-- ============================================================
-- BUZZ Pro — تتبّع هوية الجهاز مع كل بصمة (لاكتشاف مشاركة جهاز بين موظفين)
-- آمن تمامًا للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة.
-- السجلّات القديمة تحصل على NULL بهذا العمود تلقائيًا — لا كسر لأي شيء قائم.
-- انسخ هذا الملف كاملًا والصقه في SQL Editor بSupabase واضغط Run
-- ============================================================

alter table attendance add column if not exists device_id text;
create index if not exists idx_attendance_device_id on attendance(device_id, recorded_at);

-- سجلّ التنبيهات: يُملأ تلقائيًا عند اكتشاف نفس الجهاز يُستخدَم لأكثر من موظف بوقت قريب
create table if not exists device_share_alerts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  device_id text,
  employee_id_1 uuid,
  employee_id_2 uuid,
  detected_at timestamptz not null default now(),
  acknowledged boolean not null default false
);

alter table device_share_alerts enable row level security;

drop policy if exists "owner reads device alerts" on device_share_alerts;
create policy "owner reads device alerts" on device_share_alerts
  for select using (business_id = public.my_business_id() and public.is_owner());

drop policy if exists "employees insert device alerts" on device_share_alerts;
create policy "employees insert device alerts" on device_share_alerts
  for insert with check (business_id = public.my_business_id());

drop policy if exists "owner updates device alerts" on device_share_alerts;
create policy "owner updates device alerts" on device_share_alerts
  for update using (business_id = public.my_business_id() and public.is_owner());

create or replace function public.set_device_alert_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_business_trigger on device_share_alerts;
create trigger set_business_trigger before insert on device_share_alerts for each row execute function public.set_device_alert_business();

NOTIFY pgrst, 'reload schema';
