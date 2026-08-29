// Supabase Edge Function: send-push-alerts
// دالة خادم تفحص كل منشأة نشطة وتُرسل إشعار دفع حقيقي (يصل حتى لو التطبيق مغلق) لو وُجد شرط حرج فعلي.
// مصمَّمة للتشغيل الدوري (مرة أو مرتين باليوم) عبر مجدوِل (pg_cron) أو أي خدمة استدعاء مجدوَل خارجية.
//
// طريقة النشر:
// 1. من لوحة Supabase → Edge Functions → Create a new function → اسمها بالضبط: send-push-alerts
// 2. الصق هذا الكود كاملًا، واحفظ/Deploy.
// 3. من Edge Functions → Secrets → أضف سرَّين:
//    VAPID_PUBLIC_KEY  = المفتاح العام (نفسه المكتوب بكود الواجهة VAPID_PUBLIC_KEY)
//    VAPID_PRIVATE_KEY = المفتاح الخاص (لا تضعه بأي مكان آخر أبدًا)
// 4. لتشغيلها تلقائيًا بجدول زمني، استخدم إما:
//    (أ) Supabase Cron (Database → Cron Jobs إن متوفرة بخطتك) تستدعي هذه الدالة كل ٦-١٢ ساعة.
//    (ب) أو خدمة مجانية خارجية (مثل cron-job.org) تستدعي رابط الدالة بجدول زمني.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY");
    const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY");
    if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
      return new Response(JSON.stringify({ error: "لم يُضبَط مفتاحا VAPID بعد بإعدادات الخادم." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    webpush.setVapidDetails("mailto:notifications@glistening-pasca-79bbb0.netlify.app", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // نجلب كل المنشآت النشطة (غير المجمَّدة/المؤرشَفة) مع بياناتها المالية الأساسية اللازمة للفحص
    const { data: businesses, error: bizErr } = await supabase.from("businesses").select("id, name").eq("active", true).eq("frozen", false).eq("archived", false);
    if (bizErr) throw bizErr;

    let sentCount = 0, checkedCount = 0;
    const results = [];

    for (const biz of businesses || []) {
      checkedCount++;
      const alerts = await checkBusinessAlerts(supabase, biz.id);
      if (alerts.length === 0) continue;

      const { data: subs } = await supabase.from("push_subscriptions").select("*").eq("business_id", biz.id);
      if (!subs || subs.length === 0) continue;

      // نتجنّب تكرار نفس التنبيه بالضبط خلال آخر ١٢ ساعة لهذه المنشأة
      const alertKey = alerts.map((a) => a.title).sort().join("|");
      const { data: recentLog } = await supabase.from("sent_notifications_log").select("id").eq("business_id", biz.id).eq("alert_key", alertKey).gte("sent_at", new Date(Date.now() - 12 * 3600 * 1000).toISOString()).limit(1);
      if (recentLog && recentLog.length > 0) continue;

      const title = `BUZZ Pro — ${biz.name}`;
      const body = alerts[0].title + (alerts.length > 1 ? ` (+${alerts.length - 1} تنبيهات أخرى)` : "");
      const payload = JSON.stringify({ title, body, url: "/" });

      for (const sub of subs) {
        try {
          await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh_key, auth: sub.auth_key } }, payload);
          sentCount++;
        } catch (pushErr) {
          console.error("Push send failed:", pushErr.statusCode, pushErr.body || pushErr.message, "| business:", biz.name);
          // اشتراك منتهي الصلاحية أو غير صالح — نحذفه بأمان لتفادي محاولات فاشلة مستقبلية
          if (pushErr.statusCode === 404 || pushErr.statusCode === 410) {
            await supabase.from("push_subscriptions").delete().eq("id", sub.id);
          }
        }
      }
      await supabase.from("sent_notifications_log").insert({ business_id: biz.id, alert_key: alertKey });
      results.push({ business: biz.name, alerts: alerts.length, sent: subs.length });
    }

    return new Response(JSON.stringify({ checked: checkedCount, sent: sentCount, details: results }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "خطأ غير متوقّع." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});

// نسخة مبسّطة من أهم فحوصات "التنبيهات الذكية" بطرف الخادم — تركّز على أخطر الحالات فقط
// (رصيد سالب، تكاليف ثابتة متأخرة) دون الحاجة لإعادة بناء محرك الحسابات الكامل بطرف الخادم.
async function checkBusinessAlerts(supabase, businessId) {
  const alerts = [];
  const { data: settings } = await supabase.from("settings").select("*").eq("business_id", businessId).maybeSingle();
  if (!settings) return alerts;

  const { data: revenue } = await supabase.from("revenue").select("amount, method").eq("business_id", businessId);
  const { data: expenses } = await supabase.from("expenses").select("amount, method").eq("business_id", businessId);
  const { data: movements } = await supabase.from("movements").select("amount, type").eq("business_id", businessId);

  const sum = (arr, f) => (arr || []).reduce((s, x) => s + (parseFloat(f(x)) || 0), 0);
  const revCash = sum((revenue || []).filter((r) => r.method === "نقد"), (r) => r.amount);
  const revBank = sum((revenue || []).filter((r) => r.method !== "نقد"), (r) => r.amount);
  const expCash = sum((expenses || []).filter((e) => e.method === "نقد"), (e) => e.amount);
  const expBank = sum((expenses || []).filter((e) => e.method !== "نقد"), (e) => e.amount);
  let moveCash = 0, moveBank = 0;
  (movements || []).forEach((m) => {
    const amt = parseFloat(m.amount) || 0;
    if (m.type === "إيداع بنك (كاش ← بنك)") { moveCash -= amt; moveBank += amt; }
    else if (m.type === "سحب من البنك (بنك ← خزنة)") { moveCash += amt; moveBank -= amt; }
    else if (m.type === "سحب المالك (كاش)") moveCash -= amt;
    else if (m.type === "سحب المالك (بنك)") moveBank -= amt;
    else if (m.type === "ضخّ رأس مال (كاش)") moveCash += amt;
    else if (m.type === "ضخّ رأس مال (بنك)") moveBank += amt;
  });
  const cashBalance = parseFloat(settings.opening_cash || 0) + revCash - expCash + moveCash;
  const bankBalance = parseFloat(settings.opening_bank || 0) + revBank - expBank + moveBank;

  if (cashBalance + bankBalance < 0) {
    alerts.push({ title: `رصيدك الإجمالي أصبح سالبًا (${(cashBalance + bankBalance).toFixed(3)} دينار)` });
  }

  const { data: fixedCosts } = await supabase.from("fixed_costs").select("name, due_date, paid").eq("business_id", businessId);
  const today = new Date().toISOString().slice(0, 10);
  const overdueFixed = (fixedCosts || []).filter((f) => f.due_date && f.due_date < today && !f.paid);
  if (overdueFixed.length > 0) {
    alerts.push({ title: `${overdueFixed.length} تكلفة ثابتة متأخرة السداد (إيجار/رواتب/غيره)` });
  }

  return alerts;
}
