-- ============================================================
-- BUZZ Pro — إضافة عمود "ساعة قفل اليوم" الناقص فعليًا من قاعدة بياناتك
-- آمن تمامًا — لن يمسح أو يغيّر أي بيانات موجودة، فقط يضيف العمود الناقص
-- انسخ هذا الملف كاملًا والصقه في SQL Editor بSupabase واضغط Run
-- ============================================================

alter table settings add column if not exists day_cutoff_hour smallint not null default 0;
alter table settings drop constraint if exists settings_day_cutoff_hour_check;
alter table settings add constraint settings_day_cutoff_hour_check check (day_cutoff_hour >= 0 and day_cutoff_hour <= 11);

-- إعادة تحميل ذاكرة الهيكل فورًا بعد إضافة العمود، لضمان عمل الحفظ مباشرة بلا انتظار
NOTIFY pgrst, 'reload schema';
