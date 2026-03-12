export type TerminalViewportFitInput = {
  currentRows: number;
  cellHeight: number;
  viewportHeight: number;
  tolerancePx?: number;
};

// 保护性收口：某些运行时里 fitAddon 会把 rows 算大 1 行左右，
// 最终表现为“滚动条已经到底，但最后几行仍被底部裁掉”。
export function clampRowsToViewport({
  currentRows,
  cellHeight,
  viewportHeight,
  tolerancePx = 1,
}: TerminalViewportFitInput): number {
  if (
    !Number.isFinite(currentRows) ||
    !Number.isFinite(cellHeight) ||
    !Number.isFinite(viewportHeight) ||
    currentRows <= 0 ||
    cellHeight <= 0 ||
    viewportHeight <= 0
  ) {
    return currentRows;
  }

  const renderedHeight = currentRows * cellHeight;
  if (renderedHeight <= viewportHeight + tolerancePx) {
    return currentRows;
  }

  return Math.max(1, Math.floor((viewportHeight + tolerancePx) / cellHeight));
}
