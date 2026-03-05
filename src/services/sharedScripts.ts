import { invokeCommand } from "../platform/commandClient";

import type {
  SharedScriptEntry,
  SharedScriptManifestScript,
  SharedScriptPresetRestoreResult,
} from "../models/types";

/** 列出全局共享脚本（优先读取 manifest，否则回退目录扫描）。 */
export async function listSharedScripts(root?: string): Promise<SharedScriptEntry[]> {
  const normalizedRoot = root?.trim();
  return invokeCommand<SharedScriptEntry[]>("list_shared_scripts", {
    root: normalizedRoot ? normalizedRoot : null,
  });
}

/** 保存共享脚本清单（manifest.json）。 */
export async function saveSharedScriptsManifest(
  scripts: SharedScriptManifestScript[],
  root?: string,
): Promise<void> {
  const normalizedRoot = root?.trim();
  await invokeCommand("save_shared_scripts_manifest", {
    scripts,
    root: normalizedRoot ? normalizedRoot : null,
  });
}

/** 恢复内置共享脚本预设（仅补齐缺失项）。 */
export async function restoreSharedScriptPresets(
  root?: string,
): Promise<SharedScriptPresetRestoreResult> {
  const normalizedRoot = root?.trim();
  return invokeCommand<SharedScriptPresetRestoreResult>("restore_shared_script_presets", {
    root: normalizedRoot ? normalizedRoot : null,
  });
}

/** 读取共享脚本文件内容。 */
export async function readSharedScriptFile(relativePath: string, root?: string): Promise<string> {
  const normalizedRoot = root?.trim();
  return invokeCommand<string>("read_shared_script_file", {
    relativePath,
    root: normalizedRoot ? normalizedRoot : null,
  });
}

/** 写入共享脚本文件内容。 */
export async function writeSharedScriptFile(
  relativePath: string,
  content: string,
  root?: string,
): Promise<void> {
  const normalizedRoot = root?.trim();
  await invokeCommand("write_shared_script_file", {
    relativePath,
    content,
    root: normalizedRoot ? normalizedRoot : null,
  });
}
