const CACHE_NAME = "ys-chat-v2";
const APP_SHELL = [
  "/",
  "/index.html",
  "/manifest.json",
  "/favicon-96x96.png",
  "/logo.ico",
  "/apple-touch-icon.png",
  "/web-app-manifest-192x192.png",
  "/web-app-manifest-512x512.png",
];

const SKIP_CACHE_PATHS = ["/api/", "/uploads/", "/downloads/"];

const isSameOriginGet = (request) => {
  if (request.method !== "GET" || request.headers.has("range")) {
    return false;
  }

  return new URL(request.url).origin === self.location.origin;
};

const shouldSkipCache = (url) =>
  SKIP_CACHE_PATHS.some((path) => url.pathname.startsWith(path));

const cacheFirst = async (request) => {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);

  if (cached) {
    fetch(request)
      .then((response) => {
        if (response.ok) {
          cache.put(request, response.clone());
        }
      })
      .catch(() => {});

    return cached;
  }

  try {
    const response = await fetch(request);
    if (response.ok) {
      cache.put(request, response.clone());
    }

    return response;
  } catch {
    return new Response("", { status: 504, statusText: "Offline" });
  }
};

const navigationFirst = async (request) => {
  const cache = await caches.open(CACHE_NAME);

  try {
    const response = await fetch(request);
    if (response.ok) {
      cache.put("/index.html", response.clone());
    }

    return response;
  } catch {
    return (await cache.match("/index.html")) || (await cache.match("/"));
  }
};

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (!isSameOriginGet(request)) {
    return;
  }

  const url = new URL(request.url);
  if (shouldSkipCache(url)) {
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(navigationFirst(request));
    return;
  }

  event.respondWith(cacheFirst(request));
});
