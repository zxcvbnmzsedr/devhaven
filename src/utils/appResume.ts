export const APP_RESUME_EVENT = "devhaven:app-resume";
export const APP_RESUME_MIN_INACTIVE_MS = 1_500;

export function dispatchAppResumeEvent() {
  if (typeof window === "undefined") {
    return;
  }

  const emitResize = () => {
    window.dispatchEvent(new Event("resize"));
  };

  window.dispatchEvent(new CustomEvent(APP_RESUME_EVENT));
  emitResize();
  window.requestAnimationFrame(() => {
    emitResize();
  });
  window.setTimeout(() => {
    emitResize();
  }, 180);
}
