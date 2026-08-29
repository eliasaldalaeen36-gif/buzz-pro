-- ============================================================
-- BUZZ Pro — إشعارات فعلية على الهاتف (حتى لو التطبيق مغلق)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  user_id uuid references auth.users(id),
  endpoint text not null,
  p256dh_key text not null,
  auth_key text not null,
  created_at timestamptz default now(),
  unique (endpoint)
);
alter table push_subscriptions enable row level security;

drop policy if exists "المستخدم يدير اشتراكاته فقط" on push_subscriptions;
create policy "المستخدم يدير اشتراكاته فقط" on push_subscriptions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- سياسة إضافية: المالك يقدر يقرأ (لا يعدّل) اشتراكات منشأته كاملة — تلزم دالة الإرسال لجلب كل الأجهزة المشتركة بمنشأة معيّنة
drop policy if exists "قراءة اشتراكات المنشأة لأغراض الإرسال" on push_subscriptions;
create policy "قراءة اشتراكات المنشأة لأغراض الإرسال" on push_subscriptions for select
  using (business_id = public.my_business_id());

-- سجلّ تنبيهات مُرسَلة — يمنع تكرار نفس الإشعار (مثل "رصيد سالب") كل ساعة بلا داعٍ
create table if not exists sent_notifications_log (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  alert_key text not null,
  sent_at timestamptz default now()
);
alter table sent_notifications_log enable row level security;
drop policy if exists "قراءة سجلّ منشأتي فقط" on sent_notifications_log;
create policy "قراءة سجلّ منشأتي فقط" on sent_notifications_log for select
  using (business_id = public.my_business_id());

-- دالة تُعيّن business_id تلقائيًا عند إضافة اشتراك جديد (من ملف تعريف المستخدم الحالي)
create or replace function public.set_push_sub_business()
returns trigger as $$
begin
  if NEW.business_id is null then
    NEW.business_id = public.my_business_id();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists set_push_sub_business_trigger on push_subscriptions;
create trigger set_push_sub_business_trigger before insert on push_subscriptions for each row execute function public.set_push_sub_business();
