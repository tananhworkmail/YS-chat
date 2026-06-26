import { createI18n } from "vue-i18n";
import en from "./locales/en";
import vi from "./locales/vi";
import cn from "./locales/cn";

const savedLocale = localStorage.getItem("locale") || "vi";

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: savedLocale,
  fallbackLocale: "vi",
  messages: {
    vi,
    en,
    cn
  }
});

export default i18n;
