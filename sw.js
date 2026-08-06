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
