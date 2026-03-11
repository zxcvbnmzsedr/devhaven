function advanceToCodePointBoundary(text: string, index: number): number {
  if (index <= 0 || index >= text.length) {
    return Math.max(0, Math.min(index, text.length));
  }

  const code = text.charCodeAt(index);
  if (code >= 0xdc00 && code <= 0xdfff) {
    return Math.min(index + 1, text.length);
  }
  return index;
}

function findCsiSequenceEnd(text: string, index: number): number | null {
  while (index < text.length) {
    const code = text.charCodeAt(index);
    if (code >= 0x40 && code <= 0x7e) {
      return index + 1;
    }
    index += 1;
  }
  return null;
}

function findStTerminatedSequenceEnd(text: string, index: number): number | null {
  while (index < text.length) {
    if (text[index] === "\u001b" && text[index + 1] === "\\") {
      return index + 2;
    }
    index += 1;
  }
  return null;
}

function findOscSequenceEnd(text: string, index: number): number | null {
  while (index < text.length) {
    if (text[index] === "\u0007") {
      return index + 1;
    }
    if (text[index] === "\u001b" && text[index + 1] === "\\") {
      return index + 2;
    }
    index += 1;
  }
  return null;
}

function findEscapeSequenceEnd(text: string, start: number): number | null {
  const marker = text[start + 1];
  if (!marker) {
    return null;
  }

  switch (marker) {
    case "[":
      return findCsiSequenceEnd(text, start + 2);
    case "]":
      return findOscSequenceEnd(text, start + 2);
    case "P":
    case "^":
    case "_":
    case "X":
      return findStTerminatedSequenceEnd(text, start + 2);
    default: {
      let index = start + 1;
      while (index < text.length) {
        const code = text.charCodeAt(index);
        if (code >= 0x30 && code <= 0x7e) {
          return index + 1;
        }
        index += 1;
      }
      return null;
    }
  }
}

function adjustTrimStartForEscapeSequence(text: string, start: number): number {
  let safeStart = advanceToCodePointBoundary(text, start);

  while (safeStart > 0) {
    const escapeIndex = text.lastIndexOf("\u001b", safeStart - 1);
    if (escapeIndex < 0) {
      break;
    }

    const sequenceEnd = findEscapeSequenceEnd(text, escapeIndex);
    if (sequenceEnd === null) {
      return text.length;
    }
    if (sequenceEnd <= safeStart) {
      break;
    }
    safeStart = advanceToCodePointBoundary(text, sequenceEnd);
  }

  return safeStart;
}

export function trimTerminalOutputTail(text: string, maxChars: number): string {
  if (maxChars <= 0) {
    return "";
  }
  if (text.length <= maxChars) {
    return text;
  }

  const safeStart = adjustTrimStartForEscapeSequence(text, text.length - maxChars);
  return text.slice(safeStart);
}
