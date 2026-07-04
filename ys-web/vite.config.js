import { createReadStream, existsSync, rmSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import AutoImport from "unplugin-auto-import/vite";
import Components from "unplugin-vue-components/vite";
import { ElementPlusResolver } from "unplugin-vue-components/resolvers";

const apkMimeType = "application/vnd.android.package-archive";
const apkDownloadHeaders = {
  "Content-Type": apkMimeType,
  "Content-Disposition": "attachment; filename=\"YS Chat.apk\"; filename*=UTF-8''YS%20Chat.apk",
  "Content-Transfer-Encoding": "binary",
  "X-Content-Type-Options": "nosniff",
  "Cache-Control": "no-store",
};

const serveApkDownload = (middlewares) => {
  middlewares.use((req, res, next) => {
    const pathname = (req.url || "").split("?")[0];
    if (pathname !== "/downloads/YSChat.apk") {
      next();
      return;
    }

    const apkPath = resolve(process.cwd(), "public", "downloads", "YSChat.apk");
    if (!existsSync(apkPath)) {
      res.statusCode = 404;
      res.end("APK not found");
      return;
    }

    if (req.method !== "GET" && req.method !== "HEAD") {
      res.statusCode = 405;
      res.setHeader("Allow", "GET, HEAD");
      res.end();
      return;
    }

    const stat = statSync(apkPath);
    Object.entries(apkDownloadHeaders).forEach(([key, value]) => res.setHeader(key, value));
    res.setHeader("Content-Length", stat.size);

    if (req.method === "HEAD") {
      res.end();
      return;
    }

    createReadStream(apkPath).pipe(res);
  });
};

const apkDownloadPlugin = () => ({
  name: "apk-download-headers",
  configureServer(server) {
    serveApkDownload(server.middlewares);
  },
  configurePreviewServer(server) {
    serveApkDownload(server.middlewares);
  },
});

const mobileDownloadCleanupPlugin = (mode) => ({
  name: "mobile-download-cleanup",
  closeBundle() {
    if (mode !== "mobile") return;
    rmSync(resolve(process.cwd(), "dist", "downloads"), { recursive: true, force: true });
  },
});

export default defineConfig(({ mode }) => {
  const devApiProxyTarget = process.env.VITE_DEV_API_PROXY_TARGET || "http://127.0.0.1:3666";

  return {
  plugins: [
    apkDownloadPlugin(),
    mobileDownloadCleanupPlugin(mode),
    vue(),
    AutoImport({
      resolvers: [ElementPlusResolver()],
    }),
    Components({
      resolvers: [ElementPlusResolver()],
    }),
  ],

  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },

  server: {
    host: "0.0.0.0",
    port: 1800,
    strictPort: true,

    allowedHosts: [
      "web.tythac.com.vn",
    ],

    proxy: {
      "/api/v1": {
        target: devApiProxyTarget,
        changeOrigin: true,
        ws: true,
      },
      "/uploads": {
        target: devApiProxyTarget,
        changeOrigin: true,
      },
    },
  },

  preview: {
    host: "0.0.0.0",
    port: 1800,
    strictPort: true,
    allowedHosts: [
      "web.tythac.com.vn",
    ],
  },
  };
});
