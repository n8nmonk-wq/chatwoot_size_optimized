<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const props = defineProps({
  featureName: {
    type: String,
    default: '',
  },
  featureDescription: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    default: 'i-lucide-zap-off',
  },
});

const route = useRoute();

const currentFeature = computed(() => {
  if (props.featureName) {
    return {
      name: props.featureName,
      desc: props.featureDescription,
      icon: props.icon,
    };
  }
  
  if (route.path.includes('captain')) {
    return {
      name: 'Captain (AI Copilot & Assistants)',
      desc: 'AI Assistant, LLM Playground, and vector embedding features have been disabled to minimize RAM & CPU consumption.',
      icon: 'i-woot-captain',
      memorySaved: '~450 MB RAM',
    };
  }
  
  return {
    name: 'Help Center & Knowledge Base',
    desc: 'Public documentation portals and article management have been disabled to reduce database overhead and memory usage.',
    icon: 'i-lucide-library-big',
    memorySaved: '~200 MB RAM',
  };
});
</script>

<template>
  <div class="flex flex-col items-center justify-center min-h-[70vh] p-8 text-center">
    <div class="w-16 h-16 mb-6 rounded-2xl bg-amber-500/10 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400">
      <span :class="[currentFeature.icon, 'text-3xl size-8']" />
    </div>

    <div class="inline-flex items-center gap-2 px-3 py-1 mb-4 text-xs font-semibold text-amber-700 bg-amber-100 rounded-full dark:bg-amber-900/40 dark:text-amber-300">
      <span class="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
      Disabled for Optimization
    </div>

    <h2 class="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100 mb-2">
      {{ currentFeature.name }}
    </h2>

    <p class="max-w-md text-sm text-slate-500 dark:text-slate-400 mb-8">
      {{ currentFeature.desc }}
    </p>

    <div class="max-w-md w-full bg-slate-50 dark:bg-slate-800/60 rounded-xl p-5 border border-slate-200/80 dark:border-slate-700/60 text-left">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-400 mb-3">
        Optimization Summary
      </h3>
      
      <div class="space-y-2.5 text-xs text-slate-600 dark:text-slate-300">
        <div class="flex items-center justify-between py-1 border-b border-slate-200/50 dark:border-slate-700/50">
          <span>Status</span>
          <span class="font-medium text-emerald-600 dark:text-emerald-400">Resource Saver Active</span>
        </div>
        <div class="flex items-center justify-between py-1 border-b border-slate-200/50 dark:border-slate-700/50">
          <span>Estimated RAM Saved</span>
          <span class="font-medium text-slate-900 dark:text-slate-100">{{ currentFeature.memorySaved || '~300 MB' }}</span>
        </div>
        <div class="flex items-center justify-between py-1">
          <span>Primary Engine</span>
          <span class="font-medium text-woot-500">WhatsApp Marketing & Meta API</span>
        </div>
      </div>
    </div>
  </div>
</template>
