import type { ControlPlaneWorkspaceTree } from "../models/controlPlane";

export function collectNotificationIdsToMarkRead(
  tree: ControlPlaneWorkspaceTree | null | undefined,
  options: {
    isActive: boolean;
    activePaneId?: string | null;
    activeSurfaceId?: string | null;
    activeTerminalSessionId?: string | null;
  },
): string[] {
  if (!options.isActive || !tree) {
    return [];
  }
  return tree.notifications
    .filter((notification) => {
      if (notification.read) {
        return false;
      }
      const hasScopedTarget = Boolean(
        notification.paneId || notification.surfaceId || notification.terminalSessionId,
      );
      if (!hasScopedTarget) {
        return true;
      }
      return (
        (options.activePaneId && notification.paneId === options.activePaneId)
        || (options.activeSurfaceId && notification.surfaceId === options.activeSurfaceId)
        || (
          options.activeTerminalSessionId
          && notification.terminalSessionId === options.activeTerminalSessionId
        )
      );
    })
    .map((notification) => notification.id);
}

export function collectNewControlPlaneNotifications(
  tree: ControlPlaneWorkspaceTree | null | undefined,
  options: { since: number; seenIds: Set<string>; notificationIds?: string[] | null | undefined },
) {
  if (!tree) {
    return [];
  }
  const explicitNotificationIds = new Set(
    (options.notificationIds ?? []).filter((notificationId): notificationId is string => Boolean(notificationId)),
  );
  return [...tree.notifications]
    .filter((notification) => {
      if (options.seenIds.has(notification.id)) {
        return false;
      }
      if (explicitNotificationIds.size > 0) {
        return explicitNotificationIds.has(notification.id);
      }
      const timestamp = notification.updatedAt ?? notification.createdAt ?? 0;
      return timestamp >= options.since;
    })
    .sort((left, right) => {
      const leftTs = left.updatedAt ?? left.createdAt ?? 0;
      const rightTs = right.updatedAt ?? right.createdAt ?? 0;
      return leftTs - rightTs;
    });
}
