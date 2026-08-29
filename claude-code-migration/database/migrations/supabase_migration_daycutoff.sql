-- ============================================================
-- BUZZ Pro — ساعة "قفل اليوم" للمنشآت التي تعمل ليلًا بعد منتصف الليل
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "التحويل لمنصة متعددة العملاء" أولًا
-- ============================================================

alter table settings add column if not exists day_cutoff_hour smallint not null default 0;
alter table settings drop constraint if exists settings_day_cutoff_hour_check;
alter table settings add constraint settings_day_cutoff_hour_check check (day_cutoff_hour >= 0 and day_cutoff_hour <= 11);

-- لا حاجة لأي صلاحيات جديدة — جدول settings محمي مسبقًا (المالك يقرأ ويكتب، الموظف يقرأ فقط)
