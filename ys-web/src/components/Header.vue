<template>
  <header class="app-header">
    <div class="logo">
      <img src="@/assets/Logo.png" alt="Logo" class="logo-img" />
      <span class="logo-text">WEB YIHSHUO</span>
    </div>
    <div class="search-container">
      <el-input
        ref="searchInput"
        placeholder="Tìm tên website..."
        v-model="searchQuery"
        @focus="showSearchMessage"
        clearable
        size="medium"
      >
        <template #prefix>
          <el-icon><Search /></el-icon>
        </template>
      </el-input>
    </div>

    <div class="header-actions">
      <span class="user-info">
        <el-icon><UserFilled /></el-icon>
        {{ userId ? userId : "Chưa đăng nhập" }}
      </span>
    </div>
  </header>
</template>
<script setup>
import { ref, onMounted, nextTick } from "vue";
import { UserFilled, Search } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
const userId = ref(null);
const searchQuery = ref("");
const searchInput = ref(null);
onMounted(() => {
  const storedUserId = localStorage.getItem("userId");
  if (storedUserId && Number(storedUserId) > 0) {
    userId.value = storedUserId;
  }
});
const showSearchMessage = () => {
  ElMessage({
    message: "⚠ Chức năng tìm kiếm đang được phát triển, vui lòng đợi!",
    type: "info",
    duration: 3000,
  });
  nextTick(() => {
    if (searchInput.value) {
      searchInput.value.blur();
    }
  });
};
</script>

<style scoped>
.app-header {
  height: 55px;
  background: #b6b7b8;
  color: white;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.logo {
  display: flex;
  align-items: center;
  gap: 10px;
}

.logo-img {
  height: 35px;
  width: auto;
}

.logo-text {
  /* Sử dụng font hệ thống thay vì Montserrat */
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica,
    Arial, sans-serif;
  font-size: 22px;
  font-weight: 800; /* Tăng độ đậm để thay thế cho font Montserrat */
  letter-spacing: 2px;
  text-transform: uppercase;
  text-shadow: 1px 1px 2px rgba(0, 0, 0, 0.3);
}

.search-container {
  flex: 1;
  max-width: 400px;

  margin: 0 20px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.user-info {
  font-size: 16px;
  font-weight: 500;
  display: flex;
  align-items: center;
  gap: 10px;
  color: rgb(2, 2, 2);
}
</style>
