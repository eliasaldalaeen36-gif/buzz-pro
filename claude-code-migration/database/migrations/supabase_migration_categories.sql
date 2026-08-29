-- ============================================================
-- BUZZ Pro — تحديث قاعدة البيانات (تصنيفات فرعية + رقم فاتورة + مورّد)
-- آمن للتشغيل على قاعدة بياناتك الحالية — لن يمسح أو يغيّر أي بيانات موجودة
-- انسخ هذا الملف كاملًا والصقه في SQL Editor في Supabase واضغط Run
-- ============================================================

alter table expenses add column if not exists subcategory text default '';
alter table expenses add column if not exists invoice_number text default '';
alter table expenses add column if not exists supplier text default '';
