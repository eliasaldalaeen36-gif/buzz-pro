-- ============================================================
-- BUZZ Pro — الحضور والانصراف بالبصمة (WebAuthn)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "التحويل لمنصة متعددة العملاء" أولًا
-- ============================================================

-- بصمات الأجهزة المسجَّلة لكل حساب (مرجع فقط — التحقق الفعلي من البصمة يحدث على جهاز الموظف نفسه)
create table if not exists webauthn_credentials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  business_id uuid references businesses(id),
  credential_id text not null,
  device_label text default '',
  created_at timestamptz default now()
);
alter table webauthn_credentials enable row level security;

drop policy if exists "manage own credentials" on webauthn_credentials;
create policy "manage own credentials" on webauthn_credentials for all using (user_id = auth.uid()) with check (user_id = auth.uid() and business_id = public.my_business_id());

drop policy if exists "owner reads business credentials" on webauthn_credentials;
create policy "owner reads business credentials" on webauthn_credentials for select using (business_id = public.my_business_id() and public.is_owner());

-- سجلّ الحضور والانصراف
create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  employee_id uuid references auth.users(id),
  type text not null check (type in ('check_in','check_out')),
  recorded_at timestamptz not null default now()
);
alter table attendance enable row level security;

drop policy if exists "employee own attendance" on attendance;
create policy "employee own attendance" on attendance for all using (
  business_id = public.my_business_id() and employee_id = auth.uid()
) with check (
  business_id = public.my_business_id() and employee_id = auth.uid()
);

drop policy if exists "owner reads business attendance" on attendance;
create policy "owner reads business attendance" on attendance for select using (
  business_id = public.my_business_id() and public.is_owner()
);

-- تعبئة business_id تلقائيًا عند الإضافة (يعتمد على my_business_id الموجودة مسبقًا)
create or replace function public.set_attendance_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_business_trigger on attendance;
create trigger set_business_trigger before insert on attendance for each row execute function public.set_attendance_business();

drop trigger if exists set_business_trigger on webauthn_credentials;
create trigger set_business_trigger before insert on webauthn_credentials for each row execute function public.set_attendance_business();
