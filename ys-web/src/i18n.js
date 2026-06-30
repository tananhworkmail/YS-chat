import { createI18n } from "vue-i18n";
import en from "./locales/en";
import vi from "./locales/vi";
import cn from "./locales/cn";

const supportedLocales = ["vi", "en", "cn"];
const normalizeLocale = (value) => {
  if (value === "zhcn" || value === "zh-CN" || value === "zh-Hans" || value === "zh-TW" || value === "tw") return "cn";
  return supportedLocales.includes(value) ? value : "vi";
};

const savedLocale = normalizeLocale(localStorage.getItem("locale"));
localStorage.setItem("locale", savedLocale);

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
