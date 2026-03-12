import assert from "node:assert/strict";
import test from "node:test";

import { clampRowsToViewport } from "./terminalViewportFit.ts";

test("clampRowsToViewport keeps rows when rendered height fits viewport", () => {
  assert.equal(
    clampRowsToViewport({
      currentRows: 40,
      cellHeight: 18,
      viewportHeight: 721,
    }),
    40,
  );
});

test("clampRowsToViewport trims one overflow row", () => {
  assert.equal(
    clampRowsToViewport({
      currentRows: 40,
      cellHeight: 18,
      viewportHeight: 700,
    }),
    38,
  );
});

test("clampRowsToViewport grows rows when viewport can fit more content", () => {
  assert.equal(
    clampRowsToViewport({
      currentRows: 36,
      cellHeight: 18,
      viewportHeight: 721,
    }),
    40,
  );
});

test("clampRowsToViewport ignores invalid measurements", () => {
  assert.equal(
    clampRowsToViewport({
      currentRows: 40,
      cellHeight: 0,
      viewportHeight: 700,
    }),
    40,
  );
});
