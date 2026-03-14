import type { ControlPlaneWorkspaceTree } from "../models/controlPlane";

export function collectNotificationIdsToMarkRead(
  tree: ControlPlaneWorkspaceTree | null | undefined,
  options: { isActive: boolean },
): string[] {
  if (!options.isActive || !tree) {
    return [];
  }
  return tree.notifications
    .filter((notification) => !notification.read)
    .map((notification) => notification.id);
}

export function collectNewControlPlaneNotifications(
  tree: ControlPlaneWorkspaceTree | null | undefined,
  options: { since: number; seenIds: Set<string> },
) {
  if (!tree) {
    return [];
  }
  return [...tree.notifications]
    .filter((notification) => {
      const timestamp = notification.updatedAt ?? notification.createdAt ?? 0;
      return timestamp >= options.since && !options.seenIds.has(notification.id);
    })
    .sort((left, right) => {
      const leftTs = left.updatedAt ?? left.createdAt ?? 0;
      const rightTs = right.updatedAt ?? right.createdAt ?? 0;
      return leftTs - rightTs;
    });
}
