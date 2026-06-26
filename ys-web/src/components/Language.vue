<template>
  <el-dialog
    :title="$t('menu.dialogTitle')"
    v-model="dialogVisible"
    width="400px"
  >
    <el-select
      v-model="selectedLocale"
      placeholder="Select language"
      style="width: 100%"
    >
      <el-option
        v-for="lang in languages"
        :key="lang.value"
        :label="lang.label"
        :value="lang.value"
      />
    </el-select>

   <template #footer class="dialog-footer">
      <el-button @click="cancel">{{ $t("menu.cancel") }}</el-button>
      <el-button type="primary" @click="apply">{{
        $t("menu.apply")
      }}</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref } from "vue";
import { useI18n } from "vue-i18n";

const { locale } = useI18n();
const dialogVisible = ref(false);
const selectedLocale = ref(locale.value);

const languages = [
  { label: "Tiếng Việt", value: "vi" },
  { label: "English", value: "en" },
  { label: "中文", value: "zhcn" },
];

// Functions to control dialog
const open = () => {
  selectedLocale.value = locale.value;
  dialogVisible.value = true;
};

const cancel = () => {
  dialogVisible.value = false;
};

const apply = () => {
  locale.value = selectedLocale.value;
  dialogVisible.value = false;
};

// Expose open function to parent
defineExpose({ open });
</script>
