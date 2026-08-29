-- ============================================================
-- BUZZ Pro — إضافات لوحة تحكم المدير العام (تواصل، نشاط، سجلّ، أرشفة، مدراء متعددون)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقيتي "التعدد" و"حالة الاشتراك" أولًا
-- ============================================================

-- ============================================================
-- ١) معلومة تواصل + الأرشفة لكل محل
-- ============================================================
alter table businesses add column if not exists phone text default '';
alter table businesses add column if not exists archived boolean not null default false;

-- تعديل معلومات محل (اسم/نوع/هاتف) — للمدير العام فقط
create or replace function public.update_business_info(
  target_business_id uuid, name_in text, business_type_in text, phone_in text
)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  update businesses set name = name_in, business_type = business_type_in, phone = phone_in
  where id = target_business_id;
end;
$$ language plpgsql security definer;
grant execute on function public.update_business_info(uuid, text, text, text) to authenticated;

-- أرشفة محل (إخفاء دون حذف بياناته) — للمدير العام فقط
create or replace function public.archive_business(target_business_id uuid, archived_in boolean)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  update businesses set archived = archived_in where id = target_business_id;
end;
$$ language plpgsql security definer;
grant execute on function public.archive_business(uuid, boolean) to authenticated;

-- حذف محل نهائيًا (لا رجعة) — للمدير العام فقط، ويشترط أن يكون مؤرشفًا أولًا كخطوة أمان
create or replace function public.permanently_delete_business(target_business_id uuid)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  if not exists (select 1 from businesses where id = target_business_id and archived = true) then
    raise exception 'يجب أرشفة المحل أولًا قبل حذفه نهائيًا — إجراء أمان مقصود';
  end if;
  delete from revenue where business_id = target_business_id;
  delete from expenses where business_id = target_business_id;
  delete from fixed_costs where business_id = target_business_id;
  delete from movements where business_id = target_business_id;
  delete from debtors where business_id = target_business_id;
  delete from creditors where business_id = target_business_id;
  delete from cash_counts where business_id = target_business_id;
  delete from bank_statement_lines where business_id = target_business_id;
  delete from staff where business_id = target_business_id;
  delete from salary_transactions where business_id = target_business_id;
  delete from settings where business_id = target_business_id;
  update profiles set role = 'pending', business_id = null where business_id = target_business_id;
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  select auth.uid(), 'permanently_delete_business', target_business_id, name, 'حذف نهائي — كل البيانات أُزيلت'
  from businesses where id = target_business_id;
  delete from businesses where id = target_business_id;
end;
$$ language plpgsql security definer;
grant execute on function public.permanently_delete_business(uuid) to authenticated;

-- ============================================================
-- ٢) آخر نشاط لكل محل — للمدير العام فقط، بلا أي تفاصيل مالية (خصوصية العملاء)
-- ============================================================
create or replace view business_last_activity as
select business_id, max(updated_at) as last_activity_at
from (
  select business_id, updated_at from revenue
  union all select business_id, updated_at from expenses
  union all select business_id, updated_at from movements
  union all select business_id, updated_at from cash_counts
  union all select business_id, updated_at from fixed_costs
  union all select business_id, updated_at from staff
  union all select business_id, updated_at from salary_transactions
  union all select business_id, updated_at from bank_statement_lines
) t
where public.is_super_admin()
group by business_id;

grant select on business_last_activity to authenticated;

-- ============================================================
-- ٣) سجلّ أفعال المدير العام (مين أوقف مين، متى، ولماذا)
-- ============================================================
create table if not exists admin_actions_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references auth.users(id),
  action text not null,
  target_business_id uuid references businesses(id) on delete set null,
  target_business_name text default '',
  details text default '',
  created_at timestamptz default now()
);
alter table admin_actions_log enable row level security;
alter table admin_actions_log add column if not exists target_business_name text default '';
drop policy if exists "super admin only" on admin_actions_log;
create policy "super admin only" on admin_actions_log for all using (public.is_super_admin()) with check (public.is_super_admin());

-- تسجيل تلقائي: كل استدعاء لتغيير حالة محل يُسجَّل بالسجلّ
create or replace function public.set_business_status(
  target_business_id uuid, active_in boolean, frozen_in boolean, expires_at_in date, admin_message_in text
)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  update businesses set active = active_in, frozen = frozen_in, expires_at = expires_at_in, admin_message = admin_message_in
  where id = target_business_id;
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  select auth.uid(), 'set_business_status', target_business_id, name,
    format('active=%s frozen=%s expires_at=%s', active_in, frozen_in, coalesce(expires_at_in::text,'—'))
  from businesses where id = target_business_id;
end;
$$ language plpgsql security definer;

create or replace function public.create_business(business_name text, business_type_in text, owner_user_id uuid)
returns uuid as $$
declare
  new_business_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  insert into businesses (name, business_type) values (business_name, business_type_in) returning id into new_business_id;
  update profiles set role = 'owner', business_id = new_business_id where id = owner_user_id;
  insert into settings (business_id) values (new_business_id);
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  values (auth.uid(), 'create_business', new_business_id, business_name, '');
  return new_business_id;
end;
$$ language plpgsql security definer;

create or replace function public.archive_business(target_business_id uuid, archived_in boolean)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء للمدير العام فقط';
  end if;
  update businesses set archived = archived_in where id = target_business_id;
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  select auth.uid(), case when archived_in then 'archive_business' else 'unarchive_business' end, target_business_id, name, ''
  from businesses where id = target_business_id;
end;
$$ language plpgsql security definer;

-- ============================================================
-- ٤) السماح بأكثر من "مدير عام" — لمدير موجود فقط
-- ============================================================
create or replace function public.promote_to_super_admin(target_user_id uuid)
returns void as $$
begin
  if not public.is_super_admin() then
    raise exception 'صلاحية مرفوضة: هذا الإجراء لمدير عام موجود فقط';
  end if;
  update profiles set role = 'super_admin', business_id = null where id = target_user_id;
  insert into admin_actions_log (admin_id, action, target_business_id, target_business_name, details)
  values (auth.uid(), 'promote_to_super_admin', null, '', target_user_id::text);
end;
$$ language plpgsql security definer;
grant execute on function public.promote_to_super_admin(uuid) to authenticated;

-- تحديث صلاحية قراءة "businesses" لتخفي المؤرشفة افتراضيًا من قوائم غير المدير (لا تغيير فعلي مطلوب، RLS الحالية تكفي)
