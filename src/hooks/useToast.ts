import { useCallback, useEffect, useRef, useState } from "react";

export type ToastState = { message: string; variant: "success" | "error" } | null;

export type UseToastReturn = {
  toast: ToastState;
  showToast: (message: string, variant?: "success" | "error") => void;
};

/** 统一管理全局 Toast 的展示与自动关闭。 */
export function useToast(): UseToastReturn {
  const [toast, setToast] = useState<ToastState>(null);
  const toastTimerRef = useRef<number | null>(null);

  const showToast = useCallback((message: string, variant: "success" | "error" = "success") => {
    console.info("[codex-debug] showToast invoked", { message, variant });
    setToast({ message, variant });
    if (toastTimerRef.current) {
      window.clearTimeout(toastTimerRef.current);
    }
    toastTimerRef.current = window.setTimeout(() => {
      setToast(null);
      toastTimerRef.current = null;
    }, 1600);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) {
        window.clearTimeout(toastTimerRef.current);
      }
    };
  }, []);

  return { toast, showToast };
}
