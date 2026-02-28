import { useEffect } from "react";

const EDITABLE_SELECTOR = "input, textarea, [contenteditable]";
const TEXT_INPUT_TYPES = new Set(["", "text", "search", "email", "url", "tel", "password", "number"]);

function applyInputPolicy(element: HTMLElement): void {
  element.setAttribute("autocapitalize", "off");
  element.setAttribute("autocorrect", "off");
  element.setAttribute("spellcheck", "false");
  if ("spellcheck" in element) {
    (element as HTMLElement & { spellcheck: boolean }).spellcheck = false;
  }
}

function isTextInput(element: HTMLInputElement): boolean {
  const inputType = (element.getAttribute("type") ?? "").toLowerCase();
  return TEXT_INPUT_TYPES.has(inputType);
}

function isEditableContent(element: HTMLElement): boolean {
  const contentEditable = element.getAttribute("contenteditable");
  if (contentEditable == null) {
    return false;
  }
  return contentEditable.toLowerCase() !== "false";
}

function patchEditableElement(element: Element): void {
  if (element instanceof HTMLInputElement) {
    if (isTextInput(element)) {
      applyInputPolicy(element);
    }
    return;
  }

  if (element instanceof HTMLTextAreaElement) {
    applyInputPolicy(element);
    return;
  }

  if (element instanceof HTMLElement && isEditableContent(element)) {
    applyInputPolicy(element);
  }
}

function patchEditableTree(root: Element): void {
  patchEditableElement(root);
  root.querySelectorAll(EDITABLE_SELECTOR).forEach((element) => patchEditableElement(element));
}

export function useDisableInputCorrections(): void {
  useEffect(() => {
    if (typeof document === "undefined") {
      return;
    }

    const root = document.body;
    if (!root) {
      return;
    }

    patchEditableTree(root);

    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === "attributes") {
          if (mutation.target instanceof Element) {
            patchEditableElement(mutation.target);
          }
          return;
        }

        mutation.addedNodes.forEach((node) => {
          if (node instanceof Element) {
            patchEditableTree(node);
          }
        });
      });
    });

    observer.observe(root, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["type", "contenteditable"],
    });

    return () => observer.disconnect();
  }, []);
}
