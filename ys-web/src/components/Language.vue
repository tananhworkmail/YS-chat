<template>
  <el-dialog
    :title="$t('home.language.tooltip')"
    v-model="dialogVisible"
    width="400px"
  >
    <el-select
      v-model="selectedLocale"
      :placeholder="$t('home.language.label')"
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
      <el-button @click="cancel">{{ $t("home.actions.cancel") }}</el-button>
      <el-button type="primary" @click="apply">{{
        $t("home.actions.apply")
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
  { label: "中文", value: "cn" },
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
  localStorage.setItem("locale", selectedLocale.value);
  dialogVisible.value = false;
};

// Expose open function to parent
defineExpose({ open });
</script>
