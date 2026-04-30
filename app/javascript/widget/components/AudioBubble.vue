<script>
export default {
  props: {
    url: {
      type: String,
      default: '',
    },
  },
  computed: {
    audioUrl() {
      if (!this.url || this.url.startsWith('blob:')) return this.url;
      try {
        const urlObj = new URL(this.url);
        if (!urlObj.searchParams.has('t')) {
          urlObj.searchParams.append('t', Date.now());
        }
        return urlObj.toString();
      } catch {
        return this.url;
      }
    },
  },
};
</script>

<template>
  <audio
    v-if="url"
    controls
    preload="auto"
    :src="audioUrl"
    class="skip-context-menu mb-0.5 max-w-full"
  />
</template>
