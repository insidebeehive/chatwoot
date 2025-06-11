<script>
import { getContrastingTextColor } from '@chatwoot/utils';

export default {
  props: {
    url: {
      type: String,
      default: '',
    },
    widgetColor: {
      type: String,
      default: '',
    },
    isUserBubble: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['error'],
  data() {
    return {
      retryCount: 0,
      maxRetries: 3,
      isUrlReady: false,
    };
  },
  computed: {
    contrastingTextColor() {
      return getContrastingTextColor(this.widgetColor);
    },
    textColor() {
      return this.isUserBubble && this.widgetColor
        ? this.contrastingTextColor
        : '';
    },
  },
  watch: {
    url: {
      handler() {
        this.retryCount = 0;
        this.isUrlReady = false;
        this.checkUrlAvailability();
      },
      immediate: true,
    },
  },
  methods: {
    onAudioError() {
      this.retryCount += 1;
      if (this.retryCount < this.maxRetries) {
        this.isUrlReady = false;
        this.checkUrlAvailability();
      } else {
        this.$emit('error');
      }
    },
    onAudioLoaded() {
      this.isUrlReady = true;
    },
    timeStampAppendedURL() {
      const urlObj = new URL(this.url);
      if (!urlObj.searchParams.has('t')) {
        urlObj.searchParams.append('t', Date.now());
      }
      return urlObj.toString();
    },
    checkUrlAvailability() {
      const audio = new window.Audio();
      audio.oncanplaythrough = () => {
        this.isUrlReady = true;
      };
      audio.onerror = () => {
        this.onAudioError();
      };
      audio.src = this.url;
    },
  },
};
</script>

<template>
  <div>
    <div
      v-if="!isUrlReady"
      class="m-0 font-medium text-sm"
      :style="{ color: textColor }"
    >
      {{ $t('COMPONENTS.FILE_BUBBLE.DOWNLOAD') }}
    </div>
    <audio
      v-show="isUrlReady"
      controls
      preload="auto"
      class="skip-context-menu mb-0.5"
      @loadeddata="onAudioLoaded"
      @error="onAudioError"
    >
      <source :src="timeStampAppendedURL()" />
    </audio>
  </div>
</template>
