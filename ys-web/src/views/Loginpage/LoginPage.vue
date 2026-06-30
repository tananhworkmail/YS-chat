<template>
  <main class="login-page">
    <section class="auth-card">
      <aside class="auth-aside">
        <div class="aside-center">
          <BrandLogo size="xl" />
          <div class="aside-copy">
            <h2>{{ t("auth.app_name") }}</h2>
            <p>{{ t("auth.slogan") }}</p>
          </div>
        </div>
        <p class="copyright">@copyright by Yih Shuo Web Team</p>
      </aside>

      <div class="auth-main">
        <div class="card-top">
          <div class="brand">
            <BrandLogo size="lg" />
            <div>
              <p>{{ t("auth.brand_label") }}</p>
            </div>
          </div>

          <el-dropdown @command="changeLocale" trigger="click">
            <button class="lang-btn" type="button">
              <Languages :size="17" />
              <span>{{ currentLangText }}</span>
              <el-icon><ArrowDown /></el-icon>
            </button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="vi" :disabled="locale === 'vi'">Tiếng Việt</el-dropdown-item>
                <el-dropdown-item command="en" :disabled="locale === 'en'">English</el-dropdown-item>
                <el-dropdown-item command="cn" :disabled="locale === 'cn'">中文</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>

        <transition name="fade" mode="out-in">
          <div v-if="currentMode === 'login'" key="login" class="form-panel">
            <header class="form-header">
              <h2>{{ t("login.title") }}</h2>
              <p>{{ t("login.subtitle") }}</p>
            </header>

            <el-form :model="formLogin" class="form" @submit.prevent="handleLogin">
              <div class="form-group">
                <label>{{ t("common.username") }}</label>
                <el-input
                  v-model="formLogin.userid"
                  :placeholder="t('login.placeholder_user')"
                  size="large"
                  clearable
                >
                  <template #prefix><UserRound :size="18" /></template>
                </el-input>
              </div>

              <div class="form-group">
                <label>{{ t("common.password") }}</label>
                <el-input
                  v-model="formLogin.password"
                  type="password"
                  :placeholder="t('login.placeholder_pass')"
                  size="large"
                  show-password
                  clearable
                >
                  <template #prefix><LockKeyhole :size="18" /></template>
                </el-input>
              </div>

              <div class="options">
                <el-checkbox v-model="remember">{{ t("login.remember_me") }}</el-checkbox>
                <button class="text-button" type="button" @click="switchMode('forgot')">
                  {{ t("login.forgot_password") }}
                </button>
              </div>

              <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

              <el-button
                type="primary"
                size="large"
                native-type="submit"
                class="submit-btn"
                :loading="loading"
              >
                {{ t("login.submit_btn") }}
              </el-button>

              <p class="switch-line">
                <span>{{ t("login.no_account") }}</span>
                <button type="button" @click="switchMode('register')">{{ t("login.register_now") }}</button>
              </p>
            </el-form>
          </div>

          <div v-else-if="currentMode === 'register'" key="register" class="form-panel">
            <header class="form-header">
              <h2>{{ t("register.title") }}</h2>
              <p>{{ t("register.subtitle") }}</p>
            </header>

            <el-form :model="formRegister" class="form" @submit.prevent="handleRegister">
              <div class="form-grid">
                <div class="form-group">
                  <label>{{ t("common.username") }}</label>
                  <el-input
                    v-model="formRegister.userid"
                    :placeholder="t('login.placeholder_user')"
                    size="large"
                    clearable
                  >
                    <template #prefix><UserRound :size="18" /></template>
                  </el-input>
                </div>

                <div class="form-group">
                  <label>{{ t("common.fullname") }}</label>
                  <el-input
                    v-model="formRegister.fullname"
                    :placeholder="t('register.placeholder_name')"
                    size="large"
                    clearable
                  >
                    <template #prefix><IdCard :size="18" /></template>
                  </el-input>
                </div>
              </div>

              <div class="form-group">
                <label>{{ t("register.id_card_suffix") }}</label>
                <el-input
                  v-model="formRegister.idCardSuffix"
                  placeholder="12345"
                  size="large"
                  maxlength="5"
                  show-word-limit
                  clearable
                  @input="formRegister.idCardSuffix = formRegister.idCardSuffix.replace(/\D/g, '')"
                >
                  <template #prefix><BadgeCheck :size="18" /></template>
                </el-input>
              </div>

              <div class="form-grid">
                <div class="form-group">
                  <label>{{ t("common.password") }}</label>
                  <el-input
                    v-model="formRegister.password"
                    type="password"
                    :placeholder="t('login.placeholder_pass')"
                    size="large"
                    show-password
                    clearable
                  >
                    <template #prefix><LockKeyhole :size="18" /></template>
                  </el-input>
                </div>

                <div class="form-group">
                  <label>{{ t("register.confirm_password") }}</label>
                  <el-input
                    v-model="formRegister.confirmPassword"
                    type="password"
                    :placeholder="t('register.placeholder_confirm')"
                    size="large"
                    show-password
                    clearable
                  >
                    <template #prefix><LockKeyhole :size="18" /></template>
                  </el-input>
                </div>
              </div>

              <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

              <el-button
                type="primary"
                size="large"
                native-type="submit"
                class="submit-btn"
                :loading="loading"
              >
                {{ t("register.submit_btn") }}
              </el-button>

              <p class="switch-line">
                <span>{{ t("register.has_account") }}</span>
                <button type="button" @click="switchMode('login')">{{ t("register.login_now") }}</button>
              </p>
            </el-form>
          </div>

          <div v-else key="forgot" class="form-panel">
            <header class="form-header">
              <h2>{{ t("forgot.title") }}</h2>
              <p>{{ t("forgot.subtitle") }}</p>
            </header>

            <el-form :model="formForgot" class="form" @submit.prevent="handleForgotPassword">
              <div class="form-grid">
                <div class="form-group">
                  <label>{{ t("common.username") }}</label>
                  <el-input
                    v-model="formForgot.userid"
                    :placeholder="t('login.placeholder_user')"
                    size="large"
                    clearable
                  >
                    <template #prefix><UserRound :size="18" /></template>
                  </el-input>
                </div>

                <div class="form-group">
                  <label>{{ t("common.fullname") }}</label>
                  <el-input
                    v-model="formForgot.fullname"
                    :placeholder="t('register.placeholder_name')"
                    size="large"
                    clearable
                  >
                    <template #prefix><IdCard :size="18" /></template>
                  </el-input>
                </div>
              </div>

              <div class="form-group">
                <label>{{ t("forgot.birthday") }}</label>
                <el-date-picker
                  v-model="formForgot.birthday"
                  type="date"
                  :placeholder="t('forgot.placeholder_birthday')"
                  format="YYYY-MM-DD"
                  value-format="YYYY-MM-DD"
                  size="large"
                  class="date-input"
                />
              </div>

              <div class="form-group">
                <label>{{ t("forgot.id_card") }}</label>
                <el-input
                  v-model="formForgot.idCard"
                  :placeholder="t('forgot.placeholder_id')"
                  size="large"
                  clearable
                >
                  <template #prefix><BadgeCheck :size="18" /></template>
                </el-input>
              </div>

              <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

              <el-button
                type="primary"
                size="large"
                native-type="submit"
                class="submit-btn"
                :loading="loading"
              >
                {{ t("forgot.submit_btn") }}
              </el-button>

              <p class="switch-line">
                <button type="button" @click="switchMode('login')">{{ t("forgot.back_to_login") }}</button>
              </p>
            </el-form>
          </div>
        </transition>

        <a
          class="download-app"
          :href="appDownloadUrl"
          :download="appDownloadFileName"
          type="application/vnd.android.package-archive"
          @click="handleDownloadApp"
        >
          <Smartphone :size="17" />
          <span>{{ t("auth.download_android") }}</span>
        </a>
      </div>
    </section>
  </main>
</template>

<script setup>
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { ElMessage } from "element-plus";
import { ArrowDown } from "@element-plus/icons-vue";
import {
  BadgeCheck,
  IdCard,
  Languages,
  LockKeyhole,
  Smartphone,
  UserRound,
} from "lucide-vue-next";
import { useI18n } from "vue-i18n";
import BrandLogo from "@/components/BrandLogo.vue";
import auth from "@/store/auth";

const router = useRouter();
const { t, locale } = useI18n();
const apiBaseUrl = import.meta.env.VITE_API_URL || "/api/v1";
const appDownloadUrl = "/downloads/YSChat.apk";
const appDownloadFileName = "YS Chat.apk";
const apkMimeType = "application/vnd.android.package-archive";

const currentMode = ref("login");
const loading = ref(false);
const errorMsg = ref("");
const remember = ref(false);

const formLogin = ref({ userid: "", password: "" });
const formRegister = ref({
  userid: "",
  fullname: "",
  password: "",
  confirmPassword: "",
  idCardSuffix: "",
});
const formForgot = ref({ userid: "", fullname: "", birthday: "", idCard: "" });

const currentLangText = computed(() => {
  if (locale.value === "en") return "English";
  if (locale.value === "cn") return "中文";
  return "Tiếng Việt";
});

const changeLocale = (lang) => {
  locale.value = lang;
  localStorage.setItem("locale", lang);
};

const switchMode = (mode) => {
  currentMode.value = mode;
  errorMsg.value = "";
};

const getApiErrorMessage = (err) => {
  if (err?.code === "ECONNABORTED") {
    return t("auth.error_timeout", { url: `${apiBaseUrl}/ping` });
  }

  if (!err?.response) {
    return t("auth.error_network", { url: `${apiBaseUrl}/ping` });
  }

  const errorCode = err?.response?.data?.error || "SYSTEM_ERROR";
  const translated = t(`api_errors.${errorCode}`);
  return translated === `api_errors.${errorCode}` ? errorCode : translated;
};

const handleDownloadApp = async (event) => {
  event.preventDefault();

  try {
    const response = await fetch(`${appDownloadUrl}?v=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error("APK_DOWNLOAD_FAILED");

    const blob = await response.blob();
    const apkBlob = blob.type === apkMimeType ? blob : new Blob([blob], { type: apkMimeType });
    const objectUrl = window.URL.createObjectURL(apkBlob);
    const link = document.createElement("a");

    link.href = objectUrl;
    link.download = appDownloadFileName;
    link.type = apkMimeType;
    document.body.appendChild(link);
    link.click();
    link.remove();

    window.setTimeout(() => window.URL.revokeObjectURL(objectUrl), 1000);
  } catch {
    window.location.href = appDownloadUrl;
  }
};

onMounted(() => {
  const saved = localStorage.getItem("login");
  if (!saved) return;

  try {
    const data = JSON.parse(saved);
    formLogin.value.userid = data.userid || "";
    remember.value = Boolean(formLogin.value.userid);
  } catch {
    localStorage.removeItem("login");
  }
});

const handleLogin = async () => {
  try {
    errorMsg.value = "";
    loading.value = true;

    const res = await auth.loginByAccount({
      userid: formLogin.value.userid,
      password: formLogin.value.password,
    });

    if (res?.data?.token) {
      localStorage.setItem("user_token", res.data.token);
      localStorage.setItem("account_id", res.data.account_id);
      localStorage.setItem("userid", res.data.userid);
      localStorage.setItem("fullname", res.data.fullname);
    }

    if (remember.value) {
      localStorage.setItem("login", JSON.stringify({ userid: formLogin.value.userid }));
    } else {
      localStorage.removeItem("login");
    }

    router.push("/");
  } catch (err) {
    errorMsg.value = getApiErrorMessage(err);
    ElMessage.error(errorMsg.value);
  } finally {
    loading.value = false;
  }
};

const handleRegister = async () => {
  errorMsg.value = "";

  if (
    !formRegister.value.userid ||
    !formRegister.value.password ||
    !formRegister.value.fullname ||
    !formRegister.value.idCardSuffix
  ) {
    errorMsg.value = t("common.error_empty_fields");
    return;
  }

  if (!/^\d{5}$/.test(formRegister.value.idCardSuffix)) {
    errorMsg.value = t("register.error_id_suffix_invalid");
    return;
  }

  if (formRegister.value.password !== formRegister.value.confirmPassword) {
    errorMsg.value = t("register.error_mismatch");
    return;
  }

  try {
    loading.value = true;
    await auth.register({
      userid: formRegister.value.userid,
      fullname: formRegister.value.fullname,
      password: formRegister.value.password,
      idCardSuffix: formRegister.value.idCardSuffix,
    });

    ElMessage.success(t("register.success_msg"));
    formLogin.value.userid = formRegister.value.userid;
    switchMode("login");
  } catch (err) {
    errorMsg.value = getApiErrorMessage(err);
    ElMessage.error(errorMsg.value);
  } finally {
    loading.value = false;
  }
};

const handleForgotPassword = async () => {
  errorMsg.value = "";

  if (
    !formForgot.value.userid ||
    !formForgot.value.fullname ||
    !formForgot.value.birthday ||
    !formForgot.value.idCard
  ) {
    errorMsg.value = t("forgot.error_empty_verify");
    return;
  }

  try {
    loading.value = true;
    const res = await auth.forgotPassword({
      userid: formForgot.value.userid,
      fullname: formForgot.value.fullname,
      birthday: formForgot.value.birthday,
      idCard: formForgot.value.idCard,
    });

    ElMessage.success(res?.data?.message || t("forgot.success_msg"));
    formLogin.value.userid = formForgot.value.userid;
    switchMode("login");
  } catch (err) {
    errorMsg.value = getApiErrorMessage(err);
    ElMessage.error(errorMsg.value);
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
.login-page {
  --brand: #0891b2;
  --brand-dark: #0e7490;
  --brand-soft: #ecfeff;
  --ink: #172033;
  --muted: #64748b;
  --line: #dfe7f1;
  min-height: 100dvh;
  display: grid;
  place-items: center;
  padding: 18px;
  background: linear-gradient(135deg, #e8fbff 0%, #f7fafc 52%, #eef7fb 100%);
}

.auth-card {
  width: min(1080px, 100%);
  min-height: min(720px, calc(100dvh - 36px));
  display: grid;
  grid-template-columns: minmax(350px, 430px) minmax(0, 1fr);
  overflow: hidden;
  border-radius: 8px;
  background: #ffffff;
  border: 1px solid var(--line);
  box-shadow: 0 26px 80px rgba(15, 23, 42, 0.16);
  animation: panelEnter 0.45s ease both;
}

.auth-aside {
  position: relative;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 42px;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.1), transparent),
    linear-gradient(135deg, #0891b2 0%, #0e7490 100%);
  color: #ffffff;
  overflow: hidden;
}

.auth-aside::after {
  content: "";
  position: absolute;
  inset: auto -30% -30% -25%;
  height: 42%;
  background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.18), transparent);
  transform: rotate(-12deg);
  animation: sideSheen 5.8s ease-in-out infinite;
  pointer-events: none;
}

.auth-aside :deep(.brand-logo) {
  --logo-size: 168px;
  --logo-padding: 18px;
  box-shadow: none;
}

.aside-center {
  position: relative;
  z-index: 1;
  display: grid;
  justify-items: center;
  gap: 24px;
  text-align: center;
}

.aside-copy {
  display: grid;
  justify-items: center;
  gap: 10px;
}

.auth-aside h2,
.auth-aside p {
  margin: 0;
}

.auth-aside h2 {
  max-width: 330px;
  color: #ffffff;
  font-size: 34px;
  line-height: 1.14;
  font-weight: 900;
}

.auth-aside p {
  max-width: 310px;
  color: rgba(255, 255, 255, 0.82);
  font-size: 15px;
  line-height: 1.5;
  font-weight: 700;
}

.auth-main {
  min-width: 0;
  display: grid;
  align-content: center;
  gap: 24px;
  padding: 40px 44px;
}

.card-top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.brand {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 12px;
}

.brand :deep(.brand-logo) {
  box-shadow: none;
}

.brand p,
.form-header h2,
.form-header p,
.switch-line,
.error {
  margin: 0;
}

.brand p {
  color: var(--brand);
  font-size: 24px;
  font-weight: 850;
  text-transform: uppercase;
  letter-spacing: 0;
}

.lang-btn {
  height: 36px;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 0 10px;
  background: #f8fafc;
  color: #334155;
  cursor: pointer;
  font: inherit;
  font-size: 13px;
  font-weight: 750;
  transition: transform 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
}

.lang-btn:hover {
  transform: translateY(-1px);
  border-color: rgba(8, 145, 178, 0.32);
  box-shadow: 0 8px 18px rgba(8, 145, 178, 0.12);
}

.form-panel {
  display: grid;
  gap: 20px;
}

.form-header {
  display: grid;
  gap: 5px;
}

.form-header h2 {
  color: var(--ink);
  font-size: 24px;
  line-height: 1.2;
  font-weight: 900;
}

.form-header p {
  color: var(--muted);
  font-size: 14px;
  line-height: 1.45;
}

.form {
  display: grid;
  gap: 15px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.form-group {
  min-width: 0;
  display: grid;
  gap: 7px;
}

.form-group label {
  color: #26354b;
  font-size: 13px;
  font-weight: 800;
}

:deep(.el-input__wrapper) {
  min-height: 46px;
  border-radius: 8px;
  background: #fbfdff;
  box-shadow: 0 0 0 1px var(--line) inset !important;
  transition: box-shadow 0.18s ease, background-color 0.18s ease;
}

:deep(.el-input__wrapper.is-focus) {
  background: #ffffff;
  box-shadow: 0 0 0 1px var(--brand) inset, 0 0 0 3px rgba(8, 145, 178, 0.13) !important;
}

:deep(.el-input__prefix) {
  color: #728097;
}

.date-input {
  width: 100%;
}

.options {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.text-button,
.switch-line button {
  border: 0;
  background: transparent;
  color: var(--brand);
  cursor: pointer;
  font: inherit;
  font-size: 14px;
  font-weight: 800;
  padding: 0;
}

.text-button:hover,
.switch-line button:hover {
  color: var(--brand-dark);
}

.error {
  border-radius: 8px;
  border: 1px solid #fecaca;
  background: #fff1f2;
  color: #b91c1c;
  padding: 9px 11px;
  font-size: 13px;
  font-weight: 700;
  line-height: 1.4;
}

.submit-btn {
  --el-button-bg-color: var(--brand);
  --el-button-border-color: var(--brand);
  --el-button-hover-bg-color: var(--brand-dark);
  --el-button-hover-border-color: var(--brand-dark);
  --el-button-active-bg-color: var(--brand-dark);
  --el-button-active-border-color: var(--brand-dark);
  width: 100%;
  height: 46px;
  border-radius: 8px;
  font-weight: 850;
  box-shadow: 0 12px 24px rgba(8, 145, 178, 0.2);
}

.submit-btn:hover {
  transform: translateY(-1px);
}

.switch-line {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--muted);
  font-size: 14px;
}

.download-app {
  width: fit-content;
  min-width: 123px;
  height: 42px;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  justify-self: center;
  gap: 8px;
  padding: 0 16px;
  color: #ffffff;
  background: var(--brand);
  border: 1px solid rgba(255, 255, 255, 0.26);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06), 0 10px 22px rgba(8, 145, 178, 0.24);
  text-decoration: none;
  font-size: 14px;
  font-weight: 850;
  transition: transform 0.2s ease, background-color 0.2s ease, box-shadow 0.2s ease;
}

.download-app svg {
  color: #a5f3fc;
  stroke-width: 2.5;
}

.download-app:hover {
  transform: translateY(-1px);
  background: var(--brand-dark);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08), 0 14px 26px rgba(8, 145, 178, 0.28);
}

.copyright {
  position: absolute;
  left: 10px;
  bottom: 10px;
  z-index: 1;
  margin: 0;
  color: rgba(255, 255, 255, 0.7);
  font-size: 12px !important;
  font-weight: 600;
  line-height: 1.4;
  text-align: left;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.18s ease, transform 0.18s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  transform: translateY(8px);
}

@keyframes panelEnter {
  from {
    opacity: 0;
    transform: translateY(14px) scale(0.985);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes sideSheen {
  0%,
  42% {
    transform: translateX(-30%) rotate(-12deg);
    opacity: 0;
  }
  58% {
    opacity: 1;
  }
  100% {
    transform: translateX(42%) rotate(-12deg);
    opacity: 0;
  }
}

@media (max-width: 760px) {
  .auth-card {
    width: min(460px, 100%);
    min-height: 0;
    grid-template-columns: 1fr;
  }

  .auth-aside {
    display: none;
  }
}

@media (max-width: 560px) {
  .login-page {
    padding: 0;
    align-items: stretch;
  }

  .auth-card {
    width: 100%;
    min-height: 100dvh;
    border: 0;
    border-radius: 0;
    box-shadow: none;
    align-content: start;
    padding: 20px;
  }

  .auth-main {
    padding: 0;
    align-content: start;
  }

  .card-top {
    align-items: center;
  }

  .lang-btn span {
    display: none;
  }

  .form-grid {
    grid-template-columns: 1fr;
  }
}
</style>
