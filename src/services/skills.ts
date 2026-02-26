import { invoke } from "@tauri-apps/api/core";

import type {
  GlobalSkillInstallRequest,
  GlobalSkillInstallResult,
  GlobalSkillsSnapshot,
} from "../models/types";

/** 读取全局 Skills 列表（聚合 ~/.agents 与各 Agent 全局目录）。 */
export async function listGlobalSkills(): Promise<GlobalSkillsSnapshot> {
  return invoke<GlobalSkillsSnapshot>("list_global_skills");
}

/** 安装全局 Skill（由后端内置安装流程执行）。 */
export async function installGlobalSkill(
  request: GlobalSkillInstallRequest,
): Promise<GlobalSkillInstallResult> {
  return invoke<GlobalSkillInstallResult>("install_global_skill", { request });
}
