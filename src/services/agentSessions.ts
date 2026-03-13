import type { AgentSessionRecord, AgentSessionsFile } from "../models/agentSessions";
import { invokeCommand } from "../platform/commandClient";

const LOAD_AGENT_SESSION_REGISTRY_COMMAND = "load_agent_session_registry";
const UPSERT_AGENT_SESSION_RECORD_COMMAND = "upsert_agent_session_record";
const DELETE_AGENT_SESSION_RECORD_COMMAND = "delete_agent_session_record";
const LIST_AGENT_SESSION_RECORDS_COMMAND = "list_agent_session_records";

export async function loadAgentSessionRegistry(): Promise<AgentSessionsFile> {
  return invokeCommand<AgentSessionsFile>(LOAD_AGENT_SESSION_REGISTRY_COMMAND);
}

export async function upsertAgentSessionRecord(
  record: AgentSessionRecord,
): Promise<AgentSessionRecord> {
  return invokeCommand<AgentSessionRecord>(UPSERT_AGENT_SESSION_RECORD_COMMAND, { record });
}

export async function deleteAgentSessionRecord(id: string): Promise<void> {
  await invokeCommand<void>(DELETE_AGENT_SESSION_RECORD_COMMAND, { id });
}

export async function listAgentSessionRecords(
  projectPath?: string | null,
): Promise<AgentSessionRecord[]> {
  return invokeCommand<AgentSessionRecord[]>(LIST_AGENT_SESSION_RECORDS_COMMAND, {
    projectPath: projectPath ?? null,
  });
}
