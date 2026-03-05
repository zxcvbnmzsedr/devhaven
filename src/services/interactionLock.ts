import { invokeCommand } from "../platform/commandClient";

export type InteractionLockState = {
  locked: boolean;
  reason?: string | null;
};

export async function getInteractionLockState(): Promise<InteractionLockState> {
  return invokeCommand<InteractionLockState>("get_interaction_lock_state");
}

