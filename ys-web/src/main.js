import "./assets/main.css";
import { createApp } from "vue";
import ElementPlus from "element-plus";
import "element-plus/dist/index.css";
import App from "./App.vue";
import router from "./router";
import { createPinia } from "pinia";

import i18n from "./i18n";

const pinia = createPinia();
const app = createApp(App);
app.use(router);

app.use(pinia);
app.use(i18n);
app.use(ElementPlus);
app.mount("#app");

if ("serviceWorker" in navigator && import.meta.env.PROD) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch((error) => {
      console.warn("Service worker registration failed:", error);
    });
  });
}
