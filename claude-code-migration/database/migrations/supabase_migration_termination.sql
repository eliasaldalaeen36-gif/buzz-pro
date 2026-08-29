-- ============================================================
-- BUZZ Pro — إنهاء خدمة الموظف: تاريخ الإنهاء + مكافأة نهاية خدمة (تُدخَل يدويًا)
-- آمن تمامًا للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- كل الموظفين الحاليين يحصلون على NULL/صفر افتراضيًا — لا كسر لأي حساب قائم
-- انسخ هذا الملف كاملًا والصقه في SQL Editor بSupabase واضغط Run
-- ============================================================

alter table staff add column if not exists termination_date date;
alter table staff add column if not exists end_of_service_amount numeric default 0;
alter table staff add column if not exists termination_note text default '';

NOTIFY pgrst, 'reload schema';
