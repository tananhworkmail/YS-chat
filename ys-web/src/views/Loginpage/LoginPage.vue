<template>
  <div class="container">
    <div class="image-bg"></div>

    <div class="auth-wrapper">
      <div class="lang-selector">
        <el-dropdown @command="changeLocale" trigger="click">
          <el-button size="default" type="info" plain class="lang-btn">
            🌐 {{ currentLangText }}
            <el-icon class="el-icon--right"><arrow-down /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="vi" :disabled="locale === 'vi'"
                >Tiếng Việt</el-dropdown-item
              >
              <el-dropdown-item command="en" :disabled="locale === 'en'"
                >English</el-dropdown-item
              >
              <el-dropdown-item command="cn" :disabled="locale === 'cn'"
                >中文</el-dropdown-item
              >
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>

      <transition name="fade-slide" mode="out-in">
        <div v-if="currentMode === 'login'" key="login" class="login-card">
          <div class="login-header">
            <img alt="Logo" class="logo" src="@/assets/Logo.png" />
            <h1 class="title">YSWeb</h1>
            <p class="subtitle">{{ t("login.subtitle") }}</p>
          </div>

          <el-form
            :model="formLogin"
            class="form"
            @submit.prevent="handleLogin"
          >
            <div class="form-group">
              <label class="label">{{ t("common.username") }}</label>
              <el-input
                v-model="formLogin.userid"
                :placeholder="t('login.placeholder_user')"
                size="large"
                clearable
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("common.password") }}</label>
              <el-input
                v-model="formLogin.password"
                type="password"
                :placeholder="t('login.placeholder_pass')"
                size="large"
                show-password
                clearable
              />
            </div>

            <div class="options">
              <el-checkbox v-model="remember">
                {{ t("login.remember_me") }}
              </el-checkbox>
              <a
                href="#"
                @click.prevent="switchMode('forgot')"
                class="link-forgot"
              >
                {{ t("login.forgot_password") }}
              </a>
            </div>

            <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

            <el-button
              type="primary"
              size="large"
              native-type="submit"
              class="login-btn"
              :loading="loading"
            >
              {{ t("login.submit_btn") }}
            </el-button>

            <div class="footer-link">
              <span>{{ t("login.no_account") }} </span>
              <a href="#" @click.prevent="switchMode('register')" class="link">
                {{ t("login.register_now") }}
              </a>
            </div>
          </el-form>
        </div>

        <div
          v-else-if="currentMode === 'register'"
          key="register"
          class="login-card"
        >
          <div class="login-header">
            <img alt="Logo" class="logo" src="@/assets/Logo.png" />
            <h1 class="title">YSWeb</h1>
            <p class="subtitle">{{ t("register.subtitle") }}</p>
          </div>

          <el-form
            :model="formRegister"
            class="form"
            @submit.prevent="handleRegister"
          >
            <div class="form-group">
              <label class="label">{{ t("common.username") }}</label>
              <el-input
                v-model="formRegister.userid"
                :placeholder="t('login.placeholder_user')"
                size="large"
                clearable
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("common.fullname") }}</label>
              <el-input
                v-model="formRegister.fullname"
                :placeholder="t('register.placeholder_name')"
                size="large"
                clearable
              />
            </div>
            <div class="form-group">
              <label class="label">{{ t("register.id_card_suffix") }}</label>
              <el-input
                v-model="formRegister.idCardSuffix"
                placeholder="12345"
                size="large"
                maxlength="5"
                show-word-limit
                clearable
                @input="
                  formRegister.idCardSuffix = formRegister.idCardSuffix.replace(
                    /\D/g,
                    '',
                  )
                "
              />
            </div>
            <div class="form-group">
              <label class="label">{{ t("common.password") }}</label>
              <el-input
                v-model="formRegister.password"
                type="password"
                :placeholder="t('login.placeholder_pass')"
                size="large"
                show-password
                clearable
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("register.confirm_password") }}</label>
              <el-input
                v-model="formRegister.confirmPassword"
                type="password"
                :placeholder="t('register.placeholder_confirm')"
                size="large"
                show-password
                clearable
              />
            </div>

            <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

            <el-button
              type="primary"
              size="large"
              native-type="submit"
              class="login-btn"
              :loading="loading"
            >
              {{ t("register.submit_btn") }}
            </el-button>

            <div class="footer-link">
              <span>{{ t("register.has_account") }} </span>
              <a href="#" @click.prevent="switchMode('login')" class="link">
                {{ t("register.login_now") }}
              </a>
            </div>
          </el-form>
        </div>

        <div
          v-else-if="currentMode === 'forgot'"
          key="forgot"
          class="login-card"
        >
          <div class="login-header">
            <img alt="Logo" class="logo" src="@/assets/Logo.png" />
            <h1 class="title">{{ t("forgot.title") }}</h1>
            <p class="subtitle">{{ t("forgot.subtitle") }}</p>
          </div>

          <el-form
            :model="formForgot"
            class="form"
            @submit.prevent="handleForgotPassword"
          >
            <div class="form-group">
              <label class="label">{{ t("common.username") }}</label>
              <el-input
                v-model="formForgot.userid"
                :placeholder="t('login.placeholder_user')"
                size="large"
                clearable
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("common.fullname") }}</label>
              <el-input
                v-model="formForgot.fullname"
                :placeholder="t('register.placeholder_name')"
                size="large"
                clearable
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("forgot.birthday") }}</label>
              <el-date-picker
                v-model="formForgot.birthday"
                type="date"
                :placeholder="t('forgot.placeholder_birthday')"
                format="YYYY-MM-DD"
                value-format="YYYY-MM-DD"
                size="large"
                style="width: 100%"
              />
            </div>

            <div class="form-group">
              <label class="label">{{ t("forgot.id_card") }}</label>
              <el-input
                v-model="formForgot.idCard"
                :placeholder="t('forgot.placeholder_id')"
                size="large"
                clearable
              />
            </div>

            <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

            <el-button
              type="primary"
              size="large"
              native-type="submit"
              class="login-btn"
              :loading="loading"
            >
              {{ t("forgot.submit_btn") }}
            </el-button>

            <div class="footer-link">
              <a href="#" @click.prevent="switchMode('login')" class="link">
                {{ t("forgot.back_to_login") }}
              </a>
            </div>
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
        <el-icon><download /></el-icon>
        <span>Tải ứng dụng Android</span>
      </a>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from "vue";
import { useRouter } from "vue-router";
import { ElMessage } from "element-plus";
import { ArrowDown, Download } from "@element-plus/icons-vue";
import { useI18n } from "vue-i18n";
import auth from "@/store/auth"; // Thư viện call API (axios)

const router = useRouter();
const { t, locale } = useI18n();
const apiBaseUrl = import.meta.env.VITE_API_URL || "/api/v1";
const appDownloadUrl = "/downloads/YSChat.apk";
const appDownloadFileName = "YSChat.apk";
const apkMimeType = "application/vnd.android.package-archive";

const currentMode = ref("login");
const loading = ref(false);
const errorMsg = ref("");

const formLogin = ref({ userid: "", password: "" });
const remember = ref(false);

const formRegister = ref({
  userid: "",
  fullname: "",
  password: "",
  confirmPassword: "",
  idCardSuffix: "",
});

const formForgot = ref({ userid: "", fullname: "", birthday: "", idCard: "" });

const currentLangText = computed(() => {
  if (locale.value === "vi") return "Tiếng Việt";
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
    return `Không kết nối được máy chủ sau 15 giây. Hãy kiểm tra backend đang chạy và LDPlayer mở được ${apiBaseUrl}/ping.`;
  }

  if (!err?.response) {
    return `Không kết nối được máy chủ. Trong LDPlayer hãy mở trình duyệt và thử ${apiBaseUrl}/ping. Nếu không mở được, Windows Firewall đang chặn hoặc IP backend chưa đúng.`;
  }

  const errorCode = err?.response?.data?.error || "SYSTEM_ERROR";
  const translated = t(`api_errors.${errorCode}`);
  return translated === `api_errors.${errorCode}` ? errorCode : translated;
};

const handleDownloadApp = async (event) => {
  event.preventDefault();

  try {
    const response = await fetch(`${appDownloadUrl}?v=${Date.now()}`, {
      cache: "no-store",
    });
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
  if (saved) {
    const data = JSON.parse(saved);
    formLogin.value.userid = data.userid;
    remember.value = true;
  }
});

// ==========================================
// 1. XỬ LÝ ĐĂNG NHẬP
// ==========================================
const handleLogin = async () => {
  try {
    errorMsg.value = "";
    loading.value = true;

    const res = await auth.loginByAccount({
      userid: formLogin.value.userid,
      password: formLogin.value.password,
    });

    // Lưu Token vào LocalStorage
    if (res?.data?.token) {
      localStorage.setItem("user_token", res.data.token);

      // Có thể lưu thêm thông tin User nếu cần
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

// ==========================================
// 2. XỬ LÝ ĐĂNG KÝ
// ==========================================
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

  const suffixRegex = /^\d{5}$/;
  if (!suffixRegex.test(formRegister.value.idCardSuffix)) {
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
    // THÊM DÒNG NÀY ĐỂ XEM LỖI JS THỰC SỰ LÀ GÌ:
    console.error("Chi tiết lỗi Đăng ký:", err);

    errorMsg.value = getApiErrorMessage(err);
    ElMessage.error(errorMsg.value);
  } finally {
    loading.value = false;
  }
};

// ==========================================
// 3. XỬ LÝ QUÊN MẬT KHẨU
// ==========================================
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
.container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  position: relative;
  padding: 20px;
  box-sizing: border-box;
}

/* NỀN CỐ ĐỊNH */
.image-bg {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-image: url("@/assets/background.jpg");
  background-size: cover;
  background-position: center;
  background-repeat: no-repeat;
  z-index: 0;
}

/* KHUNG WRAPPER BAO BỌC NÚT NGÔN NGỮ VÀ CARD */
.auth-wrapper {
  position: relative;
  z-index: 2;
  width: 100%;
  max-width: 420px;
  display: flex;
  flex-direction: column;
  gap: 12px; /* Khoảng cách giữa nút ngôn ngữ và Card */
}

/* KHU VỰC CHỌN NGÔN NGỮ */
.lang-selector {
  display: flex;
  justify-content: flex-end; /* Đẩy nút về bên phải */
}
.lang-btn {
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.8) !important;
  backdrop-filter: blur(8px);
  border: 1px solid rgba(255, 255, 255, 0.5);
  color: #333 !important;
}

/* KHUNG CARD FORM */
.login-card {
  width: 100%;
  padding: 40px 30px;
  border-radius: 16px;
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  background: rgba(255, 255, 255, 0.9);
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
  box-sizing: border-box;
}

/* Các đoạn CSS còn lại của bạn giữ nguyên bên dưới... */
.logo {
  width: 80px;
  margin-bottom: 10px;
}
.title {
  font-size: 24px;
  font-weight: 700;
  color: black;
  margin-bottom: 5px;
}
.subtitle {
  font-size: 14px;
  color: #666;
  margin-bottom: 20px;
}
.login-header {
  text-align: center;
  margin-bottom: 20px;
}
.form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.label {
  font-size: 14px;
  font-weight: 600;
  color: #333;
}
:deep(.el-input__wrapper) {
  border-radius: 10px;
  padding: 10px;
}
:deep(.el-date-editor.el-input) {
  width: 100%;
  height: 50px;
}
.options {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 14px;
}
.link-forgot {
  color: #f56c6c;
  text-decoration: none;
  font-weight: 500;
  transition: 0.3s;
}
.link-forgot:hover {
  color: #f78989;
  text-decoration: underline;
}
.error {
  color: red;
  font-size: 13px;
  margin: 0;
  text-align: center;
}
.login-btn {
  width: 100%;
  border-radius: 10px;
  font-weight: 600;
  transition: 0.3s;
  margin-top: 5px;
  height: 45px;
}
.login-btn:hover {
  transform: scale(1.02);
}
.footer-link {
  text-align: center;
  font-size: 14px;
  margin-top: 10px;
  color: #666;
}
.footer-link .link {
  color: #409eff;
  text-decoration: none;
  font-weight: 600;
  transition: color 0.3s;
}
.footer-link .link:hover {
  color: #66b1ff;
  text-decoration: underline;
}
.download-app {
  height: 46px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #ffffff;
  background: #0f8fda;
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow: 0 10px 24px rgba(15, 143, 218, 0.28);
  text-decoration: none;
  font-size: 14px;
  font-weight: 700;
  transition:
    transform 0.2s ease,
    background 0.2s ease,
    box-shadow 0.2s ease;
}
.download-app:hover {
  background: #087fc5;
  box-shadow: 0 12px 28px rgba(8, 127, 197, 0.32);
  transform: translateY(-1px);
}
.fade-slide-enter-active,
.fade-slide-leave-active {
  transition: all 0.3s ease;
}
.fade-slide-enter-from {
  opacity: 0;
  transform: translateY(20px);
}
.fade-slide-leave-to {
  opacity: 0;
  transform: translateY(-20px);
}
@media screen and (max-width: 480px) {
  .login-card {
    padding: 30px 20px;
  }
  .title {
    font-size: 22px;
  }
  .logo {
    width: 65px;
  }
}
</style>
