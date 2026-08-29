-- ============================================================
-- BUZZ Pro — الساعات الإضافية بمعدل أجر مختلف
-- آمن تمامًا للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة.
-- كل الموظفين الحاليين يحصلون على المعدَّل الافتراضي (١.٢٥) تلقائيًا — لا كسر لأي حساب قائم.
-- انسخ هذا الملف كاملًا والصقه في SQL Editor بSupabase واضغط Run
-- ============================================================

alter table staff add column if not exists overtime_multiplier numeric default 1.25;
alter table staff drop constraint if exists staff_overtime_multiplier_check;
alter table staff add constraint staff_overtime_multiplier_check check (overtime_multiplier >= 0 and overtime_multiplier <= 3);

NOTIFY pgrst, 'reload schema';
