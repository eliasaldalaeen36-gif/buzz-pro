// BUZZ Pro — Service Worker
// استراتيجية "الشبكة أولًا": يحاول جلب أحدث نسخة دائمًا عند توفر الإنترنت،
// ولا يستخدم النسخة المخزَّنة إلا عند انعدام الاتصال فعليًا — هذا يمنع تكرار
// مشكلة "الشاشة القديمة المخزَّنة" التي واجهناها سابقًا مع اسم الملف الثابت.
const CACHE_NAME = "buzzpro-v1";

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    fetch(event.request)
      .then((res) => {
        const resClone = res.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, resClone));
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});

// استقبال إشعارات الدفع (Push) — تعمل حتى لو التطبيق مغلق تمامًا أو الهاتف مقفل،
// طالما المتصفح مثبَّت والصلاحية مفعّلة (نفس آلية أي تطبيق حقيقي يرسل إشعارات).
self.addEventListener("push", (event) => {
  let data = { title: "BUZZ Pro", body: "لديك تنبيه جديد", url: "/" };
  try { if (event.data) data = { ...data, ...event.data.json() }; } catch (e) { /* استخدام القيم الافتراضية أعلاه */ }
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      dir: "rtl",
      lang: "ar",
      data: { url: data.url || "/" },
    })
  );
});

// الضغط على الإشعار يفتح التطبيق (أو يركّز على تبويب مفتوح مسبقًا إن وُجد)
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientsArr) => {
      for (const client of clientsArr) {
        if ("focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});

// إشعارات فعلية — تعمل حتى لو التطبيق مغلق تمامًا أو الهاتف بجيب صاحبه
self.addEventListener("push", (event) => {
  let payload = { title: "BUZZ Pro", body: "لديك تنبيه جديد.", severity: "warning" };
  try { if (event.data) payload = { ...payload, ...event.data.json() }; } catch (e) {}
  const iconBySeverity = { critical: "🔴", warning: "🟡", good: "🟢" };
  event.waitUntil(
    self.registration.showNotification(`${iconBySeverity[payload.severity] || "🔔"} ${payload.title}`, {
      body: payload.body,
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      tag: payload.tag || "buzz-alert",
      dir: "rtl",
      lang: "ar",
      data: { url: payload.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && "focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
