-- ============================================================
-- BUZZ Pro — التحكم بحالة اشتراك كل محل (تفعيل/تجميد/تاريخ انتهاء/رسالة)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "التحويل لمنصة متعددة العملاء" أولًا
-- ============================================================

alter table businesses add column if not exists frozen boolean not null default false;
alter table businesses add column if not exists expires_at date;
alter table businesses add column if not exists admin_message text default '';

-- دالة تتحقق: هل محل المستخدم الحالي فعّال ومسموح له بالدخول الآن؟
create or replace function public.is_my_business_active()
returns boolean as $$
  select exists (
    select 1 from businesses
    where id = public.my_business_id()
      and active = true
      and frozen = false
      and (expires_at is null or expires_at >= current_date)
  );
$$ language sql security definer stable;

-- دالة آمنة للمدير العام فقط: تعديل حالة أي محل
create or replace function public.set_business_status(
  target_business_id uuid,
  active_in boolean,
  frozen_in boolean,
  expires_at_in date,
  admin_message_in text
)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  update businesses set
    active = active_in,
    frozen = frozen_in,
    expires_at = expires_at_in,
    admin_message = admin_message_in
  where id = target_business_id;
end;
$$ language plpgsql security definer;

grant execute on function public.set_business_status(uuid, boolean, boolean, date, text) to authenticated;

-- إعادة كتابة صلاحيات كل جداول البيانات: إضافة شرط "المحل فعّال الآن" فوق شرط الفصل بين المحلات
-- (تبقى قراءة صف "businesses" نفسه ممكنة دائمًا، ليقدر صاحب الحساب يرى رسالة الإيقاف ولماذا)

drop policy if exists "biz owner full access" on revenue;
create policy "biz owner full access" on revenue for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());
drop policy if exists "biz employee today only" on revenue;
create policy "biz employee today only" on revenue for all using (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date);

drop policy if exists "biz owner full access" on expenses;
create policy "biz owner full access" on expenses for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());
drop policy if exists "biz employee today only" on expenses;
create policy "biz employee today only" on expenses for all using (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date);

drop policy if exists "biz owner full access" on movements;
create policy "biz owner full access" on movements for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());
drop policy if exists "biz employee today only" on movements;
create policy "biz employee today only" on movements for all using (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date) with check (business_id = public.my_business_id() and public.is_employee() and public.is_my_business_active() and date = current_date);

drop policy if exists "biz full access same business" on cash_counts;
create policy "biz full access same business" on cash_counts for all using (business_id = public.my_business_id() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_my_business_active());

drop policy if exists "biz owner only" on fixed_costs;
create policy "biz owner only" on fixed_costs for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "biz owner only" on debtors;
create policy "biz owner only" on debtors for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "biz owner only" on creditors;
create policy "biz owner only" on creditors for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "biz owner only" on bank_statement_lines;
create policy "biz owner only" on bank_statement_lines for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "biz owner only" on staff;
create policy "biz owner only" on staff for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "biz owner only" on salary_transactions;
create policy "biz owner only" on salary_transactions for all using (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()) with check (business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active());

drop policy if exists "settings owner writes" on settings;
create policy "settings owner writes" on settings for all using (
  business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()
) with check (
  business_id = public.my_business_id() and public.is_owner() and public.is_my_business_active()
);
-- ملاحظة: قراءة الإعدادات (settings read own business) تبقى بلا شرط تفعيل، لتقدر الواجهة تعمل بشكل طبيعي حتى شاشة الإيقاف
