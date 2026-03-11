import assert from "node:assert/strict";
import test from "node:test";

import { trimTerminalOutputTail } from "./terminalEscapeTrim.ts";

test("trimTerminalOutputTail keeps the plain-text tail", () => {
  assert.equal(trimTerminalOutputTail("abcdef", 4), "cdef");
});

test("trimTerminalOutputTail skips a partial OSC sequence", () => {
  const osc = "\u001b]11;rgb:0000/2b2b/3636\u0007";
  const text = `prefix${osc}tail`;
  const maxChars = osc.length + "tail".length - 3;

  assert.equal(trimTerminalOutputTail(text, maxChars), "tail");
});

test("trimTerminalOutputTail skips a partial CSI sequence", () => {
  const csi = "\u001b[?1;2c";
  const text = `prefix${csi}tail`;
  const maxChars = csi.length + "tail".length - 2;

  assert.equal(trimTerminalOutputTail(text, maxChars), "tail");
});
