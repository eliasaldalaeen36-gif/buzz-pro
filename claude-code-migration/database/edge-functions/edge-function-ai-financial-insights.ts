// Supabase Edge Function: ai-financial-insights
// دالة خادم آمنة — تُخفي مفتاح API الخاص بك عن المتصفح تمامًا.
//
// طريقة النشر:
// 1. من لوحة Supabase → Edge Functions → Create a new function → اسمها بالضبط: ai-financial-insights
// 2. الصق هذا الكود كاملًا بمحرر الدالة، واحفظ/Deploy.
// 3. من Edge Functions → Secrets → أضف سرًّا جديدًا:
//    الاسم: ANTHROPIC_API_KEY
//    القيمة: مفتاحك من https://console.anthropic.com/settings/keys

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function extractJson(text: string): any {
  let cleaned = text.trim().replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/, "").trim();
  try { return JSON.parse(cleaned); } catch (_) { /* نكمل للمحاولة البديلة أدناه */ }
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start !== -1 && end !== -1 && end > start) {
    return JSON.parse(cleaned.slice(start, end + 1));
  }
  throw new Error("لا يوجد كائن JSON بالنص.");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { summary, businessName, businessType } = await req.json();

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "لم يُضبَط مفتاح الذكاء الاصطناعي بعد بإعدادات الخادم (ANTHROPIC_API_KEY)." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const systemPrompt =
      "أنت كبير المستشارين الماليين لمنشآت صغيرة بالأردن (مقاهٍ، مطاعم، محلات) — خبرة عميقة، تحليل صريح ومباشر، لا مجاملة ولا حشو. " +
      "كل نصيحة يجب ترتبط برقم حقيقي محدَّد من البيانات المُعطاة. " +
      "مهم جدًا: ردّك بالكامل كائن JSON واحد صالح فقط — لا مقدّمة، لا خاتمة، لا علامات ```، يبدأ بـ { وينتهي بـ }. " +
      'الشكل المطلوب بالضبط:\n' +
      '{"healthScore":رقم من 0 إلى 100 يمثّل الصحة المالية العامة,' +
      '"headline":"جملة واحدة صريحة تلخّص الوضع",' +
      '"insights":[{"title":"عنوان قصير (٣-٥ كلمات)","detail":"جملة أو جملتان مرتبطتان برقم حقيقي","severity":"good|warning|critical"}],' +
      '"trends":[{"metric":"اسم المؤشر","direction":"up|down|stable","detail":"جملة قصيرة توضّح الاتجاه ولماذا يهم"}],' +
      '"forecast":"فقرة قصيرة (٢-٣ جمل) تتوقّع الاتجاه المرجَّح للشهر القادم إن استمر الوضع الحالي",' +
      '"actions":["إجراء عملي مختصر ١","إجراء عملي مختصر ٢","إجراء عملي مختصر ٣","إجراء عملي مختصر ٤"]}\n' +
      "قدّم بالضبط ٤ عناصر insights، ٢ عنصرين trends، و٣ عناصر actions فقط — لا تتجاوز هذا العدد إطلاقًا. " +
      "التزم بحدود صارمة للطول: title أقل من ٢٥ حرفًا، detail أقل من ٧٠ حرفًا لكل عنصر insights/trends، كل action أقل من ٦٠ حرفًا، forecast أقل من ١٢٠ حرفًا. " +
      "الإيجاز صارم وإلزامي — التزم بالعدد والطول المذكورَين تمامًا، لأن أي تجاوز سيقطع الرد قبل اكتماله.";

    const userPrompt = `منشأة: ${businessName || "غير محدَّد"} (${businessType || "غير محدَّد"})\nالبيانات:\n${JSON.stringify(summary)}`;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 27000);

    let aiResponse;
    try {
      aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-sonnet-5",
          max_tokens: 3000,
          system: systemPrompt,
          messages: [{ role: "user", content: userPrompt }],
        }),
        signal: controller.signal,
      });
    } catch (fetchErr) {
      clearTimeout(timeoutId);
      const isTimeout = fetchErr.name === "AbortError";
      console.error("Anthropic fetch failed:", fetchErr.message, "isTimeout:", isTimeout);
      return new Response(
        JSON.stringify({ error: isTimeout ? "انتهت مهلة الاتصال بالذكاء الاصطناعي — جرّب مجددًا." : `تعذّر الاتصال بالذكاء الاصطناعي: ${fetchErr.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    clearTimeout(timeoutId);

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      console.error("Anthropic API error:", aiResponse.status, errText);
      return new Response(
        JSON.stringify({ error: `فشل الاتصال بالذكاء الاصطناعي (${aiResponse.status}): ${errText.slice(0, 300)}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const data = await aiResponse.json();
    const textBlock = (data.content || []).find((c: any) => c.type === "text");
    const rawText = textBlock?.text || "";
    console.log("Raw AI response (first 500 chars):", rawText.slice(0, 500));
    console.log("stop_reason:", data.stop_reason);

    let parsed;
    try {
      parsed = extractJson(rawText);
    } catch (parseErr) {
      console.error("Failed to parse AI response. Full raw text:", rawText);
      const hint = data.stop_reason === "max_tokens" ? " (الرد انقطع قبل الاكتمال)" : "";
      return new Response(
        JSON.stringify({ error: `تعذّر تفسير رد الذكاء الاصطناعي${hint} — حاول مجددًا.` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Unhandled error:", e.message);
    return new Response(JSON.stringify({ error: e.message || "خطأ غير متوقّع." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
