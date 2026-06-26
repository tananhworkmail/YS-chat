import { createRouter, createWebHistory } from "vue-router";
import LoginPage from "@/views/Loginpage/LoginPage.vue";
import Homepage from "@/views/Homepage/Homepage.vue";

const routes = [
  {
    path: "/",
    name: "Home",
    component: Homepage,
    meta: { requiresAuth: true }, // Đánh dấu route này cần đăng nhập
  },
  {
    path: "/login",
    name: "Login",
    component: LoginPage,
    meta: { requiresAuth: false }, // Route công khai
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
});

// KIỂM TRA ĐĂNG NHẬP TRƯỚC KHI CHUYỂN TRANG
router.beforeEach((to, from, next) => {
  // Lấy token từ localStorage (hoặc bạn có thể dùng userId tuỳ logic của bạn)
  const isAuthenticated = !!localStorage.getItem("user_token");

  // 1. Nếu route yêu cầu đăng nhập MÀ người dùng chưa đăng nhập
  if (to.meta.requiresAuth && !isAuthenticated) {
    next("/login"); // Đá văng ra trang Login
  }
  // 2. Nếu người dùng ĐÃ đăng nhập MÀ lại cố tình truy cập vào trang Login
  else if (to.path === "/login" && isAuthenticated) {
    next("/"); // Đẩy ngược lại vào trang chủ (hoặc dashboard)
  }
  // 3. Các trường hợp hợp lệ khác
  else {
    next(); // Cho phép đi tiếp
  }
});

export default router;
