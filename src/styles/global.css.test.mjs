import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const stylesheetPath = path.join(import.meta.dirname, "global.css");
const stylesheet = readFileSync(stylesheetPath, "utf8");

test("terminal stylesheet does not pin xterm viewport height", () => {
  assert.match(stylesheet, /\.terminal-pane\s+\.xterm\s*\{[^}]*height:\s*100%/s);
  assert.doesNotMatch(stylesheet, /\.terminal-pane\s+\.xterm-viewport\s*\{[^}]*height:\s*100%/s);
});
