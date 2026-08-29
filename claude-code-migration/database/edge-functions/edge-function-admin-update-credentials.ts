// BUZZ Pro — Edge Function: admin-update-credentials
// يسمح لمدير عام (لأي حساب) أو مالك محل (لموظفي محله فقط، أو لنفسه) بتغيير
// اسم المستخدم و/أو كلمة المرور لحساب آخر — بأمان، دون كشف أي مفتاح حسّاس للمتصفح.
//
// طريقة النشر: من لوحة تحكم Supabase ← Edge Functions ← Deploy a new function
// ← Via Editor ← أنشئ دالة باسم "admin-update-credentials" ← الصق هذا الكود كاملًا ← Deploy

import { createClient } from "jsr:@supabase/supabase-js@2";

const USERNAME_DOMAIN = "@buzzpro.local";
const toAuthEmail = (v: string) => {
  const s = (v || "").trim();
  return s.includes("@") ? s.toLowerCase() : s.toLowerCase().replace(/\s+/g, "") + USERNAME_DOMAIN;
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { target_user_id, new_username, new_password } = await req.json();
    if (!target_user_id) {
      return new Response(JSON.stringify({ error: "target_user_id مطلوب" }), { status: 400, headers: cors });
    }
    if (!new_username && !new_password) {
      return new Response(JSON.stringify({ error: "لا يوجد شيء لتحديثه" }), { status: 400, headers: cors });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "غير مصرَّح" }), { status: 401, headers: cors });

    // عميل يمثّل المستخدم المستدعي فعليًا — يحترم صلاحياته (RLS) تمامًا كما لو استعلم هو بنفسه
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) return new Response(JSON.stringify({ error: "غير مصرَّح" }), { status: 401, headers: cors });

    const { data: callerProfile } = await callerClient.from("profiles").select("role, business_id").eq("id", caller.id).single();
    const { data: targetProfile } = await callerClient.from("profiles").select("business_id").eq("id", target_user_id).single();

    const isSuperAdmin = callerProfile?.role === "super_admin";
    const isOwnerOfTarget = callerProfile?.role === "owner" && targetProfile && targetProfile.business_id === callerProfile.business_id;

    if (!isSuperAdmin && !isOwnerOfTarget) {
      return new Response(JSON.stringify({ error: "صلاحية مرفوضة — لا يمكنك تعديل هذا الحساب" }), { status: 403, headers: cors });
    }

    // عميل إداري كامل الصلاحيات (المفتاح السرّي يبقى على الخادم فقط، لا يصل للمتصفح إطلاقًا)
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const updates: Record<string, string> = {};
    if (new_username) updates.email = toAuthEmail(new_username);
    if (new_password) {
      if (new_password.length < 6) {
        return new Response(JSON.stringify({ error: "كلمة المرور يجب ٦ خانات على الأقل" }), { status: 400, headers: cors });
      }
      updates.password = new_password;
    }

    const { error } = await adminClient.auth.admin.updateUserById(target_user_id, updates);
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400, headers: cors });

    return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: cors });
  }
});
