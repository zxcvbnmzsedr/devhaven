import { defineConfig, presetUno } from "unocss";
import transformerVariantGroup from "@unocss/transformer-variant-group";

export default defineConfig({
  presets: [presetUno()],
  transformers: [transformerVariantGroup()],
  preflights: [],
  theme: {
    colors: {
      background: "#171717",
      "secondary-background": "#1a1a1a",
      accent: "#453be7",
      text: "rgba(255, 255, 255, 0.9)",
      "secondary-text": "rgba(255, 255, 255, 0.6)",
      border: "rgba(255, 255, 255, 0.1)",

      "titlebar-bg": "#171717",
      "titlebar-border": "#2d2d2d",
      "titlebar-text": "rgba(255, 255, 255, 0.9)",
      "titlebar-icon": "rgba(255, 255, 255, 0.6)",
      "titlebar-hover": "rgba(255, 255, 255, 0.1)",

      "sidebar-bg": "#1a1a1a",
      "sidebar-border": "#2d2d2d",
      "sidebar-title": "rgba(255, 255, 255, 0.9)",
      "sidebar-secondary": "rgba(255, 255, 255, 0.6)",
      "sidebar-selected": "rgba(59, 130, 246, 0.2)",
      "sidebar-hover": "rgba(255, 255, 255, 0.05)",
      "sidebar-directory-bg": "#1c1c1c",
      "sidebar-directory-border": "#2d2d2d",

      "card-bg": "#1b1b1b",
      "card-border": "#2d2d2d",
      "card-shadow": "rgba(0, 0, 0, 0)",
      "card-hover": "rgba(255, 255, 255, 0.08)",
      "card-selected-bg": "rgba(69, 59, 231, 0.2)",
      "card-selected-border": "rgba(69, 59, 231, 0.85)",
      "card-selected-shadow": "rgba(69, 59, 231, 0.2)",

      "tag-bg": "rgba(255, 255, 255, 0.08)",
      "tag-text": "rgba(255, 255, 255, 0.9)",
      "tag-selected-bg": "rgba(59, 130, 246, 0.2)",
      "tag-count-bg": "rgba(255, 255, 255, 0.1)",

      "button-bg": "rgba(255, 255, 255, 0.08)",
      "button-hover": "rgba(255, 255, 255, 0.12)",
      "button-primary": "#3b82f6",
      "button-primary-hover": "#2563eb",

      icon: "rgba(255, 255, 255, 0.9)",
      "icon-secondary": "rgba(255, 255, 255, 0.6)",
      "icon-git": "#3b82f6",
      "icon-folder": "#3b82f6",

      "search-bg": "#1b1b1b",
      "search-border": "#2d2d2d",
      "search-text": "rgba(255, 255, 255, 0.9)",
      "search-placeholder": "rgba(255, 255, 255, 0.4)",
      "search-active-border": "#3b82f6",
      "search-active-icon": "#3b82f6",
      "search-active-bg": "#1d1d1d",
      "search-caret": "#3b82f6",
      "search-area-bg": "#171717",
      "search-area-border": "#171717",

      "neon-blue": "#6366f1",
      "neon-green": "#10b981",
      "neon-purple": "#8b5cf6",

      success: "#10b981",
      warning: "#f59e0b",
      error: "#ef4444",
      info: "#3b82f6",

      divider: "rgba(255, 255, 255, 0.05)",
      scrollbar: "rgba(255, 255, 255, 0.2)",
      "scrollbar-hover": "rgba(255, 255, 255, 0.3)",
    },
    fontSize: {
      "fs-title": "18px",
      "fs-subtitle": "16px",
      "fs-body": "14px",
      "fs-caption": "12px",
      "fs-tag": "13px",
      "fs-sidebar-title": "15px",
      "fs-sidebar-tag": "13px",
      "fs-search": "14px",
    },
    spacing: {
      sidebar: "220px",
      detail: "420px",
      "card-h": "135px",
      "card-min": "250px",
      "card-max": "400px",
      "search-area-h": "45px",
    },
    keyframes: {
      pulse: {
        "0%, 100%": { opacity: "1" },
        "50%": { opacity: "0.6" },
      },
    },
    animation: {
      pulse: "pulse 1.5s ease-in-out infinite",
    },
  },
  shortcuts: {
    btn: "inline-flex items-center justify-center px-3 py-1.5 rounded-md bg-button-bg text-text transition-colors duration-150 hover:bg-button-hover disabled:opacity-50 disabled:cursor-not-allowed",
    "btn-primary": "bg-button-primary text-white hover:bg-button-primary-hover",
    "btn-outline": "border border-border",
    "btn-danger": "bg-[rgba(239,68,68,0.2)] text-error",
    "icon-btn":
      "inline-flex items-center justify-center min-w-6 min-h-6 p-1 rounded-md text-icon-secondary transition-colors duration-150 hover:bg-button-hover hover:text-text focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent focus-visible:outline-offset-2 disabled:opacity-50 disabled:cursor-not-allowed",
    card: "flex flex-col gap-2.5 bg-card-bg border border-card-border rounded-xl p-4 min-h-[135px] transition-colors duration-150 cursor-pointer",
    "card-selected":
      "border-card-selected-border border-2 bg-card-selected-bg shadow-[0_0_0_1px_rgba(69,59,231,0.85),0_8px_16px_rgba(69,59,231,0.2)]",
    "modal-overlay": "fixed inset-0 bg-[rgba(0,0,0,0.45)] flex items-center justify-center z-50",
    "modal-panel": "bg-secondary-background border border-border rounded-xl p-5 min-w-[320px] flex flex-col gap-4",
    "tag-row-base":
      "flex items-center justify-between gap-2 px-3 py-1 rounded-none cursor-pointer text-sidebar-title text-fs-sidebar-tag transition-colors duration-150",
    "tag-row-hover": "hover:bg-sidebar-hover",
    "tag-row-selected": "bg-sidebar-selected text-text",
    "tag-pill": "inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-fs-tag",
    "tag-count": "inline-flex items-center justify-center min-w-6 px-2 py-0.5 rounded bg-sidebar-directory-bg text-fs-caption text-sidebar-secondary",
    "section-header": "flex items-center justify-between px-4 py-1",
    "section-title": "text-fs-sidebar-title font-semibold text-sidebar-title",
  },
});
