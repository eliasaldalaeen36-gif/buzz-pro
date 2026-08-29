// Supabase Edge Function: send-manual-notification
// دالة خادم لإرسال إشعار فوري يدوي (بضغطة زر) — لا علاقة لها بالتنبيهات التلقائية الدورية
// (send-push-alerts). تُستخدَم من: (١) لوحة المدير العام لبثّ رسالة لكل أصحاب المنشآت أو كل
// الموظفين عبر المنصّة، (٢) تبويب الموظفين الخاص بكل مالك لإرسال رسالة لموظفي منشأته فقط.
//
// طريقة النشر:
// 1. من لوحة Supabase → Edge Functions → Create a new function → اسمها بالضبط: send-manual-notification
// 2. الصق هذا الكود كاملًا، واحفظ/Deploy.
// 3. تستخدم نفس سرَّي VAPID_PUBLIC_KEY وVAPID_PRIVATE_KEY المُعدَّين مسبقًا لدالة send-push-alerts —
//    لا حاجة لإضافة أي سرّ جديد إن كانت تلك الدالة منشورة فعلًا.

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

    // نتحقّق من هوية وصلاحية المُرسِل عبر رمز الدخول المُرفَق بالطلب (لا نثق بأي إدخال من الواجهة بلا تحقّق)
    const authHeader = req.headers.get("Authorization") || "";
    const callerClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "تعذّر التحقّق من هوية المرسِل — سجّل دخولك من جديد." }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: callerProfile } = await supabase.from("profiles").select("role, business_id").eq("id", userData.user.id).single();
    if (!callerProfile) {
      return new Response(JSON.stringify({ error: "تعذّر تحديد صلاحية المرسِل." }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { audience, title, body, businessId: requestedBusinessId } = await req.json();
    if (!title || !body) {
      return new Response(JSON.stringify({ error: "العنوان والنص مطلوبان." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    let targetUserIds = [];
    if (audience === "all_owners" || audience === "all_employees") {
      // بثّ عبر كل المنصّة — يقتصر على المدير العام فقط
      if (callerProfile.role !== "super_admin") {
        return new Response(JSON.stringify({ error: "هذا البث الجماعي مقصور على المدير العام فقط." }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const targetRole = audience === "all_owners" ? "owner" : "employee";
      const { data: profs } = await supabase.from("profiles").select("id").eq("role", targetRole);
      targetUserIds = (profs || []).map((p) => p.id);
    } else if (audience === "business_employees") {
      // إرسال لموظفي منشأة واحدة — مسموح للمالك (لموظفيه فقط) وللمدير العام
      if (callerProfile.role !== "owner" && callerProfile.role !== "super_admin") {
        return new Response(JSON.stringify({ error: "هذا الإرسال مقصور على مالك المنشأة أو المدير العام." }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const businessId = callerProfile.role === "owner" ? callerProfile.business_id : requestedBusinessId;
      if (!businessId) {
        return new Response(JSON.stringify({ error: "تعذّر تحديد المنشأة المستهدَفة." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const { data: profs } = await supabase.from("profiles").select("id").eq("role", "employee").eq("business_id", businessId);
      targetUserIds = (profs || []).map((p) => p.id);
    } else {
      return new Response(JSON.stringify({ error: "نوع جمهور غير معروف." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (targetUserIds.length === 0) {
      return new Response(JSON.stringify({ sent: 0, targeted: 0, message: "لا يوجد مستلمون مطابقون حاليًا — تحقّق من وجود موظفين مسجَّلين مرتبطين بهذه المنشأة." }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { data: subs } = await supabase.from("push_subscriptions").select("*").in("user_id", targetUserIds);
    const payload = JSON.stringify({ title, body, url: "/" });
    let sentCount = 0;
    const failures = [];
    for (const sub of subs || []) {
      try {
        await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh_key, auth: sub.auth_key } }, payload);
        sentCount++;
      } catch (pushErr) {
        console.error("Push send failed:", pushErr.statusCode, pushErr.body || pushErr.message, "| endpoint:", sub.endpoint.slice(0, 60));
        failures.push({ status: pushErr.statusCode, message: (pushErr.body || pushErr.message || "").toString().slice(0, 200) });
        if (pushErr.statusCode === 404 || pushErr.statusCode === 410) {
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }

    return new Response(JSON.stringify({ sent: sentCount, targeted: targetUserIds.length, failures: failures.slice(0, 3) }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "خطأ غير متوقّع." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
