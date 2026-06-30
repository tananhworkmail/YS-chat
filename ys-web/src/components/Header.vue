<template>
  <header class="app-header">
    <div class="logo">
      <BrandLogo size="sm" />
      <span class="logo-text">YS CHAT</span>
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
import BrandLogo from "@/components/BrandLogo.vue";
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
  height: 58px;
  background: #ffffff;
  color: #172033;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 22px;
  border-bottom: 1px solid #dfe7f1;
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.08);
}

.logo {
  display: flex;
  align-items: center;
  gap: 10px;
}

.logo :deep(.brand-logo) {
  box-shadow: none;
}

.logo-text {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica,
    Arial, sans-serif;
  font-size: 18px;
  line-height: 1.2;
  font-weight: 900;
  letter-spacing: 0;
  text-transform: uppercase;
  color: #152238;
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
  font-size: 14px;
  font-weight: 700;
  display: flex;
  align-items: center;
  gap: 8px;
  color: #334155;
}
</style>
