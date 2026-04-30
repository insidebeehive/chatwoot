<script>
import { mapGetters } from 'vuex';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import Spinner from 'shared/components/Spinner.vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  checkFileSizeLimit,
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
} from 'shared/helpers/FileHelper';
import { DirectUpload } from 'activestorage';

export default {
  components: { FluentIcon, Spinner },
  props: {
    onAttach: {
      type: Function,
      default: () => {},
    },
  },
  data() {
    return {
      state: 'idle', // 'idle' | 'recording' | 'preview' | 'uploading'
      recordingTime: 0,
      timerInterval: null,
      recordedMimeType: '',
      previewBlob: null,
      previewUrl: null,
      previewExt: '',
      isPlaying: false,
      previewCurrentTime: 0,
      previewDuration: 0,
      wavesurfer: null,
      recordPlugin: null,
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    formattedRecordingTime() {
      return this.formatSeconds(this.recordingTime);
    },
    formattedPreviewTime() {
      const current = this.formatSeconds(Math.floor(this.previewCurrentTime));
      const total =
        this.previewDuration && !Number.isNaN(this.previewDuration)
          ? this.formatSeconds(Math.floor(this.previewDuration))
          : '0:00';
      return `${current} / ${total}`;
    },
  },
  beforeUnmount() {
    clearInterval(this.timerInterval);
    this.destroyWaveSurfer();
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
  },
  methods: {
    formatSeconds(totalSeconds) {
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    },
    getSupportedMimeType() {
      const types = [
        'audio/webm;codecs=opus',
        'audio/webm',
        'audio/ogg;codecs=opus',
        'audio/mp4',
      ];
      return types.find(type => MediaRecorder.isTypeSupported(type)) || '';
    },
    getFileExtension(mimeType) {
      if (mimeType.includes('webm')) return 'webm';
      if (mimeType.includes('ogg')) return 'ogg';
      if (mimeType.includes('mp4')) return 'mp4';
      return 'webm';
    },

    startRecording() {
      this.state = 'recording';
      this.recordingTime = 0;
      this.$nextTick(async () => {
        try {
          const mimeType = this.getSupportedMimeType();

          this.wavesurfer = WaveSurfer.create({
            container: this.$refs.waveformContainer,
            waveColor: '#EF4444',
            progressColor: '#EF4444',
            height: 28,
            barWidth: 2,
            barGap: 1,
            barRadius: 2,
            interact: false,
            normalize: true,
          });

          this.recordPlugin = RecordPlugin.create({
            scrollingWaveform: true,
            renderRecordedAudio: false,
            mimeType: mimeType || undefined,
          });

          this.wavesurfer.registerPlugin(this.recordPlugin);

          this.recordPlugin.on('record-end', async blob => {
            if (this.state === 'idle') return;
            const recordedType = blob.type || mimeType || 'audio/webm';
            const baseMimeType = recordedType.split(';')[0];
            this.recordedMimeType = recordedType;
            this.previewBlob = blob;
            this.previewExt = this.getFileExtension(baseMimeType);
            this.previewUrl = URL.createObjectURL(blob);
            await this.loadPreview();
          });

          await this.recordPlugin.startRecording();

          this.timerInterval = setInterval(() => {
            this.recordingTime += 1;
          }, 1000);
        } catch (error) {
          this.state = 'idle';
          emitter.emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('VOICE_RECORDING_ERROR'),
          });
        }
      });
    },

    async loadPreview() {
      clearInterval(this.timerInterval);

      this.wavesurfer.setOptions({
        waveColor: '#1F93FF',
        progressColor: '#1F93FF',
        interact: true,
      });

      await this.wavesurfer.load(this.previewUrl);

      this.previewDuration = this.wavesurfer.getDuration();
      this.previewCurrentTime = 0;

      this.wavesurfer.on('audioprocess', () => {
        this.previewCurrentTime = this.wavesurfer.getCurrentTime();
      });

      this.wavesurfer.on('finish', () => {
        this.isPlaying = false;
        this.previewCurrentTime = 0;
      });

      this.wavesurfer.on('seeking', () => {
        this.previewCurrentTime = this.wavesurfer.getCurrentTime();
      });

      this.state = 'preview';
    },

    stopAndPreview() {
      if (this.recordPlugin && this.state === 'recording') {
        this.recordPlugin.stopRecording();
      }
    },

    togglePlay() {
      if (!this.wavesurfer) return;
      this.wavesurfer.playPause();
      this.isPlaying = !this.isPlaying;
    },

    cancelRecording() {
      clearInterval(this.timerInterval);
      this.state = 'idle';
      this.destroyWaveSurfer();
      if (this.previewUrl) {
        URL.revokeObjectURL(this.previewUrl);
        this.previewUrl = null;
      }
      this.previewBlob = null;
      this.recordingTime = 0;
      this.isPlaying = false;
      this.previewCurrentTime = 0;
      this.previewDuration = 0;
    },

    destroyWaveSurfer() {
      if (this.wavesurfer) {
        try {
          this.wavesurfer.destroy();
        } catch {
          // ignore destroy errors
        }
        this.wavesurfer = null;
        this.recordPlugin = null;
      }
    },

    async sendRecording() {
      if (!this.previewBlob) return;
      this.state = 'uploading';
      try {
        const baseMimeType = this.recordedMimeType.split(';')[0];
        const file = new File(
          [this.previewBlob],
          `voice-${Date.now()}.${this.previewExt}`,
          { type: baseMimeType }
        );

        this.destroyWaveSurfer();
        if (this.previewUrl) {
          URL.revokeObjectURL(this.previewUrl);
          this.previewUrl = null;
        }

        if (checkFileSizeLimit(file, DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE)) {
          if (this.globalConfig.directUploadsEnabled) {
            await this.onDirectFileUpload(file);
          } else {
            await this.onIndirectFileUpload(file);
          }
        } else {
          emitter.emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('FILE_SIZE_LIMIT', {
              MAXIMUM_FILE_UPLOAD_SIZE: DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
            }),
          });
        }
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('UPLOAD_ERROR'),
        });
      }
      this.previewBlob = null;
      this.state = 'idle';
    },

    async onDirectFileUpload(file) {
      try {
        const { websiteToken } = window.chatwootWebChannel;
        const upload = new DirectUpload(
          file,
          `/api/v1/widget/direct_uploads?website_token=${websiteToken}`,
          {
            directUploadWillCreateBlobWithXHR: xhr => {
              xhr.setRequestHeader('X-Auth-Token', window.authToken);
            },
          }
        );
        await new Promise((resolve, reject) => {
          upload.create((error, blob) => {
            if (error) {
              reject(error);
            } else {
              this.onAttach({
                file: blob.signed_id,
                thumbUrl: URL.createObjectURL(file),
                fileType: 'audio',
              });
              resolve();
            }
          });
        });
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: error.message || this.$t('UPLOAD_ERROR'),
        });
      }
    },

    async onIndirectFileUpload(file) {
      try {
        await this.onAttach({
          file,
          thumbUrl: URL.createObjectURL(file),
          fileType: 'audio',
        });
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('UPLOAD_ERROR'),
        });
      }
    },
  },
};
</script>

<template>
  <!-- Idle -->
  <button
    v-if="state === 'idle'"
    class="flex items-center justify-center min-h-8 min-w-8"
    @click="startRecording"
  >
    <FluentIcon icon="mic" class="text-n-slate-12" />
  </button>

  <!-- Recording & Preview (shared waveform container) -->
  <div
    v-else-if="state === 'recording' || state === 'preview'"
    class="flex items-center gap-1.5 bg-n-alpha-2 rounded-xl px-2 py-0.5 border border-n-container"
  >
    <button
      class="flex items-center justify-center size-6 shrink-0"
      @click="cancelRecording"
    >
      <FluentIcon icon="dismiss" size="14" class="text-n-slate-10" />
    </button>

    <button
      v-if="state === 'preview'"
      class="flex items-center justify-center size-6 shrink-0"
      @click="togglePlay"
    >
      <svg
        v-if="!isPlaying"
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="currentColor"
        class="text-n-slate-12"
      >
        <path d="M8 5v14l11-7z" />
      </svg>
      <svg
        v-else
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="currentColor"
        class="text-n-slate-12"
      >
        <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
      </svg>
    </button>

    <div ref="waveformContainer" class="w-24 overflow-hidden" />

    <span
      class="text-xs tabular-nums whitespace-nowrap shrink-0"
      :class="state === 'recording' ? 'text-red-500' : 'text-n-slate-10'"
    >
      <span
        v-if="state === 'recording'"
        class="inline-block w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse mr-0.5 align-middle"
      />
      {{
        state === 'recording' ? formattedRecordingTime : formattedPreviewTime
      }}
    </span>

    <button
      v-if="state === 'recording'"
      class="flex items-center justify-center size-6 shrink-0"
      @click="stopAndPreview"
    >
      <span class="w-3 h-3 rounded-sm bg-red-500 inline-block" />
    </button>
    <button
      v-else
      class="flex items-center justify-center size-6 shrink-0"
      @click="sendRecording"
    >
      <FluentIcon icon="send" size="16" class="text-n-brand" />
    </button>
  </div>

  <!-- Uploading -->
  <div
    v-else-if="state === 'uploading'"
    class="flex items-center justify-center min-h-8 min-w-8"
  >
    <Spinner size="small" />
  </div>
</template>
