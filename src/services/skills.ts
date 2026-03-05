import { invokeCommand } from "../platform/commandClient";

import type {
  GlobalSkillInstallRequest,
  GlobalSkillInstallResult,
  GlobalSkillUninstallRequest,
  GlobalSkillsSnapshot,
} from "../models/types";

/** 读取全局 Skills 列表（聚合 ~/.agents 与各 Agent 全局目录）。 */
export async function listGlobalSkills(): Promise<GlobalSkillsSnapshot> {
  return invokeCommand<GlobalSkillsSnapshot>("list_global_skills");
}

/** 安装全局 Skill（由后端内置安装流程执行）。 */
export async function installGlobalSkill(
  request: GlobalSkillInstallRequest,
): Promise<GlobalSkillInstallResult> {
  return invokeCommand<GlobalSkillInstallResult>("install_global_skill", { request });
}

/** 从指定 Agent 卸载全局 Skill。 */
export async function uninstallGlobalSkill(
  request: GlobalSkillUninstallRequest,
): Promise<GlobalSkillInstallResult> {
  return invokeCommand<GlobalSkillInstallResult>("uninstall_global_skill", { request });
}
