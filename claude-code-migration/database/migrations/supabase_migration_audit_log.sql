-- ============================================================
-- BUZZ Pro — سجلّ التدقيق (من أضاف/عدّل ماذا ومتى)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية حساب الموظف (supabase_migration_employee_role.sql) أولًا
-- ============================================================

-- أعمدة التدقيق لكل جدول بيانات رئيسي
alter table revenue add column if not exists created_by uuid references auth.users(id);
alter table revenue add column if not exists updated_by uuid references auth.users(id);
alter table revenue add column if not exists updated_at timestamptz;

alter table expenses add column if not exists created_by uuid references auth.users(id);
alter table expenses add column if not exists updated_by uuid references auth.users(id);
alter table expenses add column if not exists updated_at timestamptz;

alter table movements add column if not exists created_by uuid references auth.users(id);
alter table movements add column if not exists updated_by uuid references auth.users(id);
alter table movements add column if not exists updated_at timestamptz;

alter table debtors add column if not exists created_by uuid references auth.users(id);
alter table debtors add column if not exists updated_by uuid references auth.users(id);
alter table debtors add column if not exists updated_at timestamptz;

alter table creditors add column if not exists created_by uuid references auth.users(id);
alter table creditors add column if not exists updated_by uuid references auth.users(id);
alter table creditors add column if not exists updated_at timestamptz;

alter table cash_counts add column if not exists created_by uuid references auth.users(id);
alter table cash_counts add column if not exists updated_by uuid references auth.users(id);
alter table cash_counts add column if not exists updated_at timestamptz;

alter table fixed_costs add column if not exists created_by uuid references auth.users(id);
alter table fixed_costs add column if not exists updated_by uuid references auth.users(id);
alter table fixed_costs add column if not exists updated_at timestamptz;

alter table staff add column if not exists created_by uuid references auth.users(id);
alter table staff add column if not exists updated_by uuid references auth.users(id);
alter table staff add column if not exists updated_at timestamptz;

alter table salary_transactions add column if not exists created_by uuid references auth.users(id);
alter table salary_transactions add column if not exists updated_by uuid references auth.users(id);
alter table salary_transactions add column if not exists updated_at timestamptz;

alter table bank_statement_lines add column if not exists created_by uuid references auth.users(id);
alter table bank_statement_lines add column if not exists updated_by uuid references auth.users(id);
alter table bank_statement_lines add column if not exists updated_at timestamptz;

-- دالة تعبئة أعمدة التدقيق تلقائيًا: من الخادم مباشرة، لا يعتمد على أي شيء يرسله المتصفح
create or replace function public.set_audit_fields()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    NEW.created_by = auth.uid();
    NEW.updated_by = auth.uid();
    NEW.updated_at = now();
  elsif TG_OP = 'UPDATE' then
    NEW.created_by = OLD.created_by; -- يبقى منشئ السجل الأصلي دون تغيير
    NEW.updated_by = auth.uid();
    NEW.updated_at = now();
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists audit_trigger on revenue;
create trigger audit_trigger before insert or update on revenue for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on expenses;
create trigger audit_trigger before insert or update on expenses for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on movements;
create trigger audit_trigger before insert or update on movements for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on debtors;
create trigger audit_trigger before insert or update on debtors for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on creditors;
create trigger audit_trigger before insert or update on creditors for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on cash_counts;
create trigger audit_trigger before insert or update on cash_counts for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on fixed_costs;
create trigger audit_trigger before insert or update on fixed_costs for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on staff;
create trigger audit_trigger before insert or update on staff for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on salary_transactions;
create trigger audit_trigger before insert or update on salary_transactions for each row execute function public.set_audit_fields();
drop trigger if exists audit_trigger on bank_statement_lines;
create trigger audit_trigger before insert or update on bank_statement_lines for each row execute function public.set_audit_fields();

-- المالك يحتاج يرى بريد أي حساب (بما فيه الموظفين) ليعمل سجلّ التدقيق بشكل صحيح
drop policy if exists "owner reads all profiles" on profiles;
create policy "owner reads all profiles" on profiles for select using (public.is_owner());

-- سجلّ موحّد لكل الجداول — للمالك فقط بغض النظر عن صلاحيات الجداول الأصلية
create or replace view audit_log with (security_invoker = true) as
select t.table_name, t.id, t.ref_date, t.amount, t.created_at, t.created_by, t.updated_at, t.updated_by,
       p1.email as created_by_email, p2.email as updated_by_email
from (
  select 'revenue' as table_name, id, date::text as ref_date, amount, created_at, created_by, updated_at, updated_by from revenue
  union all
  select 'expenses', id, date::text, amount, created_at, created_by, updated_at, updated_by from expenses
  union all
  select 'movements', id, date::text, amount, created_at, created_by, updated_at, updated_by from movements
  union all
  select 'debtors', id, date::text, amount, created_at, created_by, updated_at, updated_by from debtors
  union all
  select 'creditors', id, date::text, amount, created_at, created_by, updated_at, updated_by from creditors
  union all
  select 'cash_counts', id, date::text, actual, created_at, created_by, updated_at, updated_by from cash_counts
  union all
  select 'fixed_costs', id, null::text, monthly_amount, created_at, created_by, updated_at, updated_by from fixed_costs
  union all
  select 'staff', id, null::text, monthly_salary, created_at, created_by, updated_at, updated_by from staff
  union all
  select 'salary_transactions', id, date::text, amount, created_at, created_by, updated_at, updated_by from salary_transactions
  union all
  select 'bank_statement_lines', id, date::text, amount, created_at, created_by, updated_at, updated_by from bank_statement_lines
) t
left join profiles p1 on p1.id = t.created_by
left join profiles p2 on p2.id = t.updated_by
where public.is_owner();

grant select on audit_log to authenticated;
