// Supabase Edge Function: analyze-invoice-photo
// دالة خادم تستخدم قدرة "الرؤية" بالذكاء الاصطناعي (Claude) لقراءة صورة فاتورة مشتريات
// واستخراج: المورّد، التاريخ، المبلغ الكلي، وقائمة الأصناف الفردية (اسم/كمية/سعر وحدة).
// النتيجة تُعرَض للمراجعة والتصحيح قبل أي حفظ — لا يُحفَظ شيء تلقائيًا من هذه الدالة نفسها.
//
// طريقة النشر:
// 1. Supabase → Edge Functions → Create a new function → اسمها بالضبط: analyze-invoice-photo
// 2. الصق هذا الكود كاملًا، Deploy.
// 3. تستخدم نفس سرّ ANTHROPIC_API_KEY المُعدّ مسبقًا لدالة ai-financial-insights —
//    لا حاجة لأي سرّ جديد إن كانت تلك الدالة تعمل فعلًا.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function extractJson(text) {
  let cleaned = text.trim().replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/, "").trim();
  try { return JSON.parse(cleaned); } catch (_) {}
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start !== -1 && end !== -1 && end > start) return JSON.parse(cleaned.slice(start, end + 1));
  throw new Error("لا يوجد كائن JSON صالح بالنص.");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { imageBase64, mediaType, categories, subcategoriesByCategory } = await req.json();
    if (!imageBase64) {
      return new Response(JSON.stringify({ error: "لم تُرسَل أي صورة." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "لم يُضبَط مفتاح الذكاء الاصطناعي بعد بإعدادات الخادم (ANTHROPIC_API_KEY)." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const categoryList = Array.isArray(categories) && categories.length > 0 ? categories : ["رواتب", "إيجار", "مرافق", "تسويق", "صيانة", "نقل", "رسوم وترخيص", "عمولة توصيل", "أخرى"];
    const categoryGuideLines = categoryList.map((cat) => {
      const subs = (subcategoriesByCategory && subcategoriesByCategory[cat]) || [];
      return subs.length > 0 ? `${cat} (تصنيفات فرعية متاحة: ${subs.join("، ")})` : cat;
    }).join("\n- ");

    const systemPrompt =
      "أنت مساعد محاسبي متخصّص بفحص صور فواتير المشتريات (مقاهٍ ومطاعم ومحلات صغيرة بالأردن). " +
      "الخطوة الأولى والأهم: تحقّق هل الصورة **فاتورة مشتريات حقيقية من مورّد** (تسرد أصنافًا اشتراها صاحب المحل) — " +
      "وليست إيصال دفع ببطاقة (POS) يستلمه الزبون عند الشراء منك، ولا إيصال بيع صادر منك، ولا صورة عشوائية أو مستندًا آخر. " +
      "إيصالات نقاط البيع (POS) عادة قصيرة، لا تسرد أصنافًا متعددة بأسعار وحدة، وغالبًا تحمل عبارات مثل \"APPROVED\" أو \"رقم مرجعي\" أو \"AUTH CODE\" بدل قائمة أصناف حقيقية — هذه **ليست** فاتورة مشتريات، ارفضها. " +
      "لو لم تكن الصورة فاتورة مشتريات حقيقية، أعد فورًا: {\"isPurchaseInvoice\":false,\"reason\":\"سبب مختصر بالعربية\"} وتوقّف هنا بلا أي حقول أخرى. " +
      "مهم جدًا: قيمة isPurchaseInvoice يجب أن تكون قيمة منطقية JSON صريحة (true أو false بلا علامات اقتباس)، لا نصًا أبدًا. " +
      "لو كانت فاتورة مشتريات حقيقية، اقرأها بدقة واستخرج البيانات الحقيقية الظاهرة فقط — لا تخترع أرقامًا أو أسماء. " +
      "**لكل صنف على حدة**، اختر أنسب فئة وتصنيف فرعي من قائمة فئات هذا المحل الفعلية أدناه (قد تختلف الفئة من صنف لآخر بنفس الفاتورة — مثلًا صنف منظّفات يختلف عن صنف بن قهوة): \n- " + categoryGuideLines + "\n" +
      'ردّك بالكامل كائن JSON واحد فقط بلا أي نص إضافي، بالشكل التالي بالضبط:\n' +
      '{"isPurchaseInvoice":true,"vendor":"اسم المورّد إن ظهر، وإلا فارغ","invoiceDate":"YYYY-MM-DD إن ظهر تاريخ، وإلا فارغ",' +
      '"totalAmount":الرقم الكلي للفاتورة كرقم فقط,' +
      '"lineItems":[{"itemName":"اسم الصنف بالعربية أو كما ظهر","quantity":الكمية كرقم,"unitPrice":سعر الوحدة كرقم,"lineTotal":الإجمالي لهذا الصنف كرقم,"category":"الفئة الأنسب لهذا الصنف تحديدًا من القائمة أعلاه بالضبط","subcategory":"التصنيف الفرعي الأنسب إن وُجد بقائمة تلك الفئة، وإلا فارغ"}],' +
      '"confidence":"high أو medium أو low حسب وضوح الصورة"}\n' +
      "قدّم كل الأصناف الظاهرة بالفاتورة، لا تختصر.";

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 45000);

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
          max_tokens: 2000,
          system: systemPrompt,
          messages: [{
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: mediaType || "image/jpeg", data: imageBase64 } },
              { type: "text", text: "اقرأ هذه الفاتورة واستخرج بياناتها بالشكل المطلوب بالضبط." },
            ],
          }],
        }),
        signal: controller.signal,
      });
    } catch (fetchErr) {
      clearTimeout(timeoutId);
      const isTimeout = fetchErr.name === "AbortError";
      return new Response(
        JSON.stringify({ error: isTimeout ? "انتهت مهلة قراءة الصورة — جرّب مجددًا، أو تأكّد أن الصورة واضحة وحجمها معقول." : `تعذّر الاتصال بالذكاء الاصطناعي: ${fetchErr.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    clearTimeout(timeoutId);

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      console.error("Anthropic API error:", aiResponse.status, errText);
      return new Response(
        JSON.stringify({ error: `فشل تحليل الصورة (${aiResponse.status}): ${errText.slice(0, 300)}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const data = await aiResponse.json();
    const textBlock = (data.content || []).find((c) => c.type === "text");
    const rawText = textBlock?.text || "";

    let parsed;
    try {
      parsed = extractJson(rawText);
    } catch (parseErr) {
      console.error("Failed to parse invoice AI response:", rawText);
      return new Response(
        JSON.stringify({ error: "تعذّر تفسير نتيجة قراءة الفاتورة — جرّب صورة أوضح." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify(parsed), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "خطأ غير متوقّع." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
