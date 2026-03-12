import type { ReactNode, RefObject } from "react";
import { Fragment, useRef } from "react";

import type { SplitOrientation, TerminalPaneNode } from "../../models/terminal";

type SplitLayoutProps = {
  root: TerminalPaneNode;
  activePaneId: string;
  onResize: (path: number[], ratios: number[]) => void;
  renderPane: (paneId: string, isActive: boolean) => ReactNode;
  path?: number[];
};

type SplitDividerProps = {
  orientation: SplitOrientation;
  index: number;
  ratios: number[];
  path: number[];
  containerRef: RefObject<HTMLDivElement | null>;
  onResize: (path: number[], ratios: number[]) => void;
};

const MIN_RATIO = 0.05;

function SplitDivider({ orientation, index, ratios, path, containerRef, onResize }: SplitDividerProps) {
  const isVertical = orientation === "v";
  const cursor = isVertical ? "cursor-col-resize" : "cursor-row-resize";
  const dividerSize = isVertical ? "w-1.5" : "h-1.5";
  const dividerClass = `${dividerSize} bg-[var(--terminal-split-divider)] hover:bg-[var(--terminal-split-divider-hover)]`;

  const handleMouseDown = (event: React.MouseEvent<HTMLDivElement>) => {
    event.preventDefault();
    const container = containerRef.current;
    if (!container) {
      return;
    }
    const rect = container.getBoundingClientRect();
    const startPos = isVertical ? event.clientX : event.clientY;
    const size = isVertical ? rect.width : rect.height;
    const startRatios = [...ratios];
    const pairTotal = (startRatios[index] ?? 0) + (startRatios[index + 1] ?? 0);

    const handleMove = (moveEvent: MouseEvent) => {
      const currentPos = isVertical ? moveEvent.clientX : moveEvent.clientY;
      const delta = (currentPos - startPos) / size;
      let left = (startRatios[index] ?? 0) + delta;
      let right = (startRatios[index + 1] ?? 0) - delta;
      if (left < MIN_RATIO) {
        left = MIN_RATIO;
        right = pairTotal - left;
      }
      if (right < MIN_RATIO) {
        right = MIN_RATIO;
        left = pairTotal - right;
      }
      const nextRatios = [...startRatios];
      nextRatios[index] = left;
      nextRatios[index + 1] = right;
      onResize(path, nextRatios);
    };

    const handleUp = () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };

    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
  };

  return (
    <div
      className={`${cursor} ${dividerClass} shrink-0`}
      onMouseDown={handleMouseDown}
      role="separator"
      aria-orientation={isVertical ? "vertical" : "horizontal"}
    />
  );
}

export default function SplitLayout({
  root,
  activePaneId,
  onResize,
  renderPane,
  path = [],
}: SplitLayoutProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const isVertical = root.type === "split" ? root.orientation === "v" : true;
  const containerClass = `flex h-full w-full min-h-0 min-w-0 ${isVertical ? "flex-row" : "flex-col"}`;
  const children = root.type === "split" ? root.children : [root];
  const ratios = root.type === "split" ? root.ratios : [1];
  const showDivider = root.type === "split";

  return (
    <div ref={containerRef} className={containerClass}>
      {children.map((child, index) => {
        const ratio = ratios[index] ?? 1 / children.length;
        const childKey = child.type === "leaf" ? `pane:${child.paneId}` : `${path.join("-")}-${index}`;
        return (
          <Fragment key={childKey}>
            <div
              className="flex h-full min-h-0 min-w-0"
              style={{ flexBasis: 0, flexGrow: ratio, flexShrink: 1 }}
            >
              {child.type === "leaf" ? (
                <div className="h-full w-full min-h-0 min-w-0">
                  {renderPane(child.paneId, child.paneId === activePaneId)}
                </div>
              ) : (
                <SplitLayout
                  root={child}
                  activePaneId={activePaneId}
                  onResize={onResize}
                  renderPane={renderPane}
                  path={[...path, index]}
                />
              )}
            </div>
            {showDivider && index < children.length - 1 ? (
              <SplitDivider
                orientation={root.type === "split" ? root.orientation : "v"}
                index={index}
                ratios={ratios}
                path={path}
                containerRef={containerRef}
                onResize={onResize}
              />
            ) : null}
          </Fragment>
        );
      })}
    </div>
  );
}
