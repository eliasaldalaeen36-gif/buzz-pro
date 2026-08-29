-- ============================================================
-- BUZZ Pro — تحديث الفئات الافتراضية للمصاريف للمنشآت الجديدة فقط
-- آمن تمامًا: لا يمسّ أو يغيّر فئات أي منشأة موجودة حاليًا (بما فيها BUZZ Coffee) إطلاقًا —
-- يؤثر فقط على أي منشأة جديدة تُنشَأ بعد تشغيل هذا الملف.
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية supabase_migration_categories_per_business.sql أولًا
-- ============================================================

-- دالة تزرع الفئات العامة الافتراضية (بلا تصنيفات فرعية — حرية كاملة للمالك بإضافتها لاحقًا)
create or replace function public.seed_default_expense_categories(target_business_id uuid)
returns void as $$
begin
  insert into expense_categories (business_id, name, is_variable, sort_order) values
    (target_business_id, 'رواتب', false, 1),
    (target_business_id, 'إيجار', false, 2),
    (target_business_id, 'مرافق', false, 3),
    (target_business_id, 'تسويق', false, 4),
    (target_business_id, 'صيانة', false, 5),
    (target_business_id, 'نقل', false, 6),
    (target_business_id, 'رسوم وترخيص', false, 7),
    (target_business_id, 'عمولة توصيل', false, 8),
    (target_business_id, 'أخرى', false, 9)
  on conflict do nothing;
end;
$$ language plpgsql security definer;

-- عند إنشاء أي منشأة جديدة، تُزرَع هذه الفئات تلقائيًا — لا تأثير إطلاقًا على المنشآت الموجودة مسبقًا
create or replace function public.trg_seed_categories_on_business_insert()
returns trigger as $$
begin
  perform public.seed_default_expense_categories(NEW.id);
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists seed_categories_after_business_insert on businesses;
create trigger seed_categories_after_business_insert
  after insert on businesses
  for each row execute function public.trg_seed_categories_on_business_insert();
