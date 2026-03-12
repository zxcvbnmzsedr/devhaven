export type TerminalViewportFitInput = {
  currentRows: number;
  cellHeight: number;
  viewportHeight: number;
  tolerancePx?: number;
};

// 基于真实 viewport 高度二次校正 rows：
// - fitAddon 估大时，避免底部内容被裁掉；
// - fitAddon 估小时，避免 pane 放大后底部留下空白。
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

  const nextRows = Math.max(1, Math.floor((viewportHeight + tolerancePx) / cellHeight));
  if (nextRows === currentRows) {
    return currentRows;
  }

  return nextRows;
}
