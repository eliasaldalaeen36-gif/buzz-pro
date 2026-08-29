-- ============================================================
-- BUZZ Pro — ربط سجلّ الموظف (الرواتب) بحساب دخوله (الحضور بالبصمة)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "الحضور والانصراف بالبصمة" أولًا
-- ============================================================

alter table staff add column if not exists login_user_id uuid references auth.users(id);
alter table staff add column if not exists daily_hours numeric not null default 8;

-- لا حاجة لأي صلاحيات جديدة — جدول staff محمي مسبقًا (المالك فقط ضمن محله)
