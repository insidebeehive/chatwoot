<script>
export default {
  props: {
    url: {
      type: String,
      default: '',
    },
  },
  emits: ['error'],
  methods: {
    onAudioError() {
      this.$emit('error');
    },
    timeStampAppendedURL() {
      const urlObj = new URL(this.url);
      if (!urlObj.searchParams.has('t')) {
        urlObj.searchParams.append('t', Date.now());
      }
      return urlObj.toString();
    }
  },
};
</script>

<template>
  <audio
    controls
    preload="auto"
    class="skip-context-menu mb-0.5"
    @error="onAudioError"
  >
    <source :src="timeStampAppendedURL()" />
  </audio>
</template>
