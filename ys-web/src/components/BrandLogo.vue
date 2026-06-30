<template>
  <span class="brand-logo" :class="`brand-logo--${size}`" aria-hidden="true">
    <span class="brand-logo__crop">
      <img src="@/assets/logochat.png" alt="" />
    </span>
  </span>
</template>

<script setup>
defineProps({
  size: {
    type: String,
    default: "md",
  },
});
</script>

<style scoped>
.brand-logo {
  --logo-size: 48px;
  --logo-padding: 6px;
  --logo-radius: 8px;
  width: var(--logo-size);
  height: var(--logo-size);
  display: inline-grid;
  place-items: center;
  flex: 0 0 auto;
  padding: var(--logo-padding);
  border-radius: var(--logo-radius);
  background: #ffffff;
  border: 1px solid rgba(8, 145, 178, 0.14);
  box-shadow: 0 12px 28px rgba(15, 23, 42, 0.1);
}

.brand-logo__crop {
  width: 100%;
  aspect-ratio: 1;
  display: block;
  overflow: hidden;
}

.brand-logo__crop img {
  width: 100%;
  height: auto;
  display: block;
}

.brand-logo--sm {
  --logo-size: 40px;
  --logo-padding: 5px;
  --logo-radius: 8px;
}

.brand-logo--md {
  --logo-size: 52px;
  --logo-padding: 7px;
  --logo-radius: 8px;
}

.brand-logo--lg {
  --logo-size: 76px;
  --logo-padding: 10px;
  --logo-radius: 8px;
}

.brand-logo--xl {
  --logo-size: 96px;
  --logo-padding: 12px;
  --logo-radius: 8px;
}
</style>
