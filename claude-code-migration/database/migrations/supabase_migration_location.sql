-- ============================================================
-- BUZZ Pro — تحديد موقع المحل لتقييد الحضور والانصراف بالبصمة
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- يتطلب تشغيل ترقية "الحضور والانصراف بالبصمة" أولًا
-- ============================================================

alter table settings add column if not exists location_lat double precision;
alter table settings add column if not exists location_lng double precision;
alter table settings add column if not exists location_radius_m integer not null default 150;

-- لا حاجة لأي صلاحيات جديدة — جدول settings محمي مسبقًا (المالك يقرأ ويكتب، الموظف يقرأ فقط)
