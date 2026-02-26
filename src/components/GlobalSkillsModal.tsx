import { useCallback, useEffect, useMemo, useState } from "react";

import type {
  GlobalSkillAgent,
  GlobalSkillInstallResult,
  GlobalSkillSummary,
  GlobalSkillsSnapshot,
} from "../models/types";
import { installGlobalSkill, listGlobalSkills, uninstallGlobalSkill } from "../services/skills";
import { copyToClipboard, openInFinder } from "../services/system";
import { IconX } from "./Icons";

const DEFAULT_SKILL_SOURCE = "vercel-labs/agent-skills";

export type GlobalSkillsModalProps = {
  onClose: () => void;
};

function parseSkillNames(value: string): string[] {
  return value
    .split(/[\n,]/)
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

/** 全局 Skills 管理页，展示技能 x Agent 启用矩阵，并支持直接安装。 */
export default function GlobalSkillsModal({ onClose }: GlobalSkillsModalProps) {
  const [skillsSnapshot, setSkillsSnapshot] = useState<GlobalSkillsSnapshot>({ agents: [], skills: [] });
  const [globalSkillsLoading, setGlobalSkillsLoading] = useState(true);
  const [globalSkillsError, setGlobalSkillsError] = useState<string | null>(null);
  const [globalSkillsQuery, setGlobalSkillsQuery] = useState("");
  const [globalSkillsActionMessage, setGlobalSkillsActionMessage] = useState<string | null>(null);
  const [matrixActionKey, setMatrixActionKey] = useState<string | null>(null);

  const [installSource, setInstallSource] = useState(DEFAULT_SKILL_SOURCE);
  const [installSkillNames, setInstallSkillNames] = useState("");
  const [selectedAgentIds, setSelectedAgentIds] = useState<string[]>([]);
  const [installLoading, setInstallLoading] = useState(false);
  const [installResult, setInstallResult] = useState<GlobalSkillInstallResult | null>(null);

  const agentColumns = skillsSnapshot.agents;
  const globalSkills = skillsSnapshot.skills;

  const filteredGlobalSkills = useMemo(() => {
    const keyword = globalSkillsQuery.trim().toLowerCase();
    if (!keyword) {
      return globalSkills;
    }

    return globalSkills.filter((skill) => {
      const agentText = skill.agents.map((agent) => `${agent.id} ${agent.label}`).join(" ");
      const extraPaths = skill.paths.join(" ");
      return (
        skill.name.toLowerCase().includes(keyword) ||
        skill.description.toLowerCase().includes(keyword) ||
        skill.canonicalPath.toLowerCase().includes(keyword) ||
        extraPaths.toLowerCase().includes(keyword) ||
        agentText.toLowerCase().includes(keyword)
      );
    });
  }, [globalSkills, globalSkillsQuery]);

  const handleRefreshGlobalSkills = useCallback(async () => {
    setGlobalSkillsLoading(true);
    setGlobalSkillsError(null);
    try {
      const snapshot = await listGlobalSkills();
      setSkillsSnapshot(snapshot);
      setSelectedAgentIds((previous) => {
        const availableIds = snapshot.agents.map((agent) => agent.id);
        if (availableIds.length === 0) {
          return [];
        }
        if (previous.length === 0) {
          return availableIds;
        }
        const next = previous.filter((id) => availableIds.includes(id));
        return next.length > 0 ? next : availableIds;
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "读取技能列表失败";
      setGlobalSkillsError(message);
      setSkillsSnapshot({ agents: [], skills: [] });
    } finally {
      setGlobalSkillsLoading(false);
    }
  }, []);

  const handleCopySkillPath = useCallback(async (path: string, name: string) => {
    try {
      await copyToClipboard(path);
      setGlobalSkillsActionMessage(`已复制路径：${name}`);
    } catch (error) {
      console.error("复制技能路径失败。", error);
      setGlobalSkillsActionMessage(`复制路径失败：${name}`);
    }
  }, []);

  const handleOpenSkillPath = useCallback(async (path: string, name: string) => {
    try {
      await openInFinder(path);
      setGlobalSkillsActionMessage(`已打开目录：${name}`);
    } catch (error) {
      console.error("打开技能目录失败。", error);
      setGlobalSkillsActionMessage(`打开目录失败：${name}`);
    }
  }, []);

  const handleToggleAgent = useCallback((agentId: string) => {
    setSelectedAgentIds((previous) => {
      if (previous.includes(agentId)) {
        return previous.filter((id) => id !== agentId);
      }
      return [...previous, agentId];
    });
  }, []);

  const handleSelectAllAgents = useCallback(() => {
    setSelectedAgentIds(agentColumns.map((agent) => agent.id));
  }, [agentColumns]);

  const handleClearAgents = useCallback(() => {
    setSelectedAgentIds([]);
  }, []);

  const handleInstallSkill = useCallback(async () => {
    const source = installSource.trim();
    if (!source) {
      setGlobalSkillsActionMessage("请先填写安装来源（仓库地址或本地路径）。");
      return;
    }

    setInstallLoading(true);
    setGlobalSkillsActionMessage(null);
    setInstallResult(null);

    try {
      const result = await installGlobalSkill({
        source,
        skillNames: parseSkillNames(installSkillNames),
        agentIds: selectedAgentIds,
      });
      setInstallResult(result);
      setGlobalSkillsActionMessage("技能安装完成，已刷新最新状态。");
      await handleRefreshGlobalSkills();
    } catch (error) {
      const message = error instanceof Error ? error.message : "技能安装失败";
      setGlobalSkillsActionMessage(message);
    } finally {
      setInstallLoading(false);
    }
  }, [handleRefreshGlobalSkills, installSkillNames, installSource, selectedAgentIds]);

  const handleToggleSkillAgent = useCallback(
    async (skill: GlobalSkillSummary, agent: GlobalSkillAgent, enabled: boolean) => {
      const actionKey = `${skill.name}::${agent.id}`;
      setMatrixActionKey(actionKey);
      setGlobalSkillsActionMessage(null);
      setInstallResult(null);

      try {
        if (enabled) {
          await uninstallGlobalSkill({
            skillName: skill.name,
            canonicalPath: skill.canonicalPath,
            paths: skill.paths,
            agentId: agent.id,
          });
          setGlobalSkillsActionMessage(`已从 ${agent.label} 卸载：${skill.name}`);
        } else {
          await installGlobalSkill({
            source: skill.canonicalPath,
            skillNames: [],
            agentIds: [agent.id],
          });
          setGlobalSkillsActionMessage(`已为 ${agent.label} 安装：${skill.name}`);
        }
        await handleRefreshGlobalSkills();
      } catch (error) {
        const message = error instanceof Error ? error.message : "切换技能启用状态失败";
        setGlobalSkillsActionMessage(message);
      } finally {
        setMatrixActionKey(null);
      }
    },
    [handleRefreshGlobalSkills],
  );

  useEffect(() => {
    void handleRefreshGlobalSkills();
  }, [handleRefreshGlobalSkills]);

  return (
    <div className="modal-overlay" role="dialog" aria-modal>
      <div className="modal-panel min-w-[760px] w-[min(1280px,96vw)] max-h-[90vh] overflow-y-auto">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="text-[16px] font-semibold">Skills</div>
          </div>
          <button className="icon-btn" onClick={onClose} aria-label="关闭">
            <IconX size={14} />
          </button>
        </div>

        <section className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div>
            <div className="text-[13px] font-semibold">安装 Skill</div>
          </div>

          <div className="grid gap-2 md:grid-cols-2">
            <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
              安装来源（仓库地址 / 本地路径）
              <input
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                value={installSource}
                onChange={(event) => setInstallSource(event.target.value)}
                placeholder="vercel-labs/agent-skills"
              />
            </label>
            <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
              Skill 名称（可选，逗号分隔）
              <input
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                value={installSkillNames}
                onChange={(event) => setInstallSkillNames(event.target.value)}
                placeholder="如：find-skills, skill-creator"
              />
            </label>
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2 text-[12px] text-secondary-text">
              <span>目标 Agents（不选则默认安装到全部 Agent）</span>
              <div className="flex items-center gap-2">
                <button className="btn btn-outline !px-2 !py-1 text-[11px]" onClick={handleSelectAllAgents}>
                  全选
                </button>
                <button className="btn btn-outline !px-2 !py-1 text-[11px]" onClick={handleClearAgents}>
                  清空
                </button>
              </div>
            </div>
            {agentColumns.length === 0 ? (
              <div className="text-fs-caption text-secondary-text">暂无可选 Agent。</div>
            ) : (
              <div className="flex flex-wrap gap-2">
                {agentColumns.map((agent) => {
                  const selected = selectedAgentIds.includes(agent.id);
                  return (
                    <button
                      key={`install-agent-${agent.id}`}
                      className={`rounded-md border px-2 py-1 text-[11px] transition-colors duration-150 ${
                        selected
                          ? "border-accent bg-[rgba(69,59,231,0.16)] text-accent"
                          : "border-border bg-button-bg text-secondary-text hover:bg-button-hover"
                      }`}
                      onClick={() => handleToggleAgent(agent.id)}
                    >
                      {selected ? "已选" : "未选"} · {agent.label}
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button className="btn btn-primary" onClick={() => void handleInstallSkill()} disabled={installLoading}>
              {installLoading ? "安装中..." : "安装 Skill"}
            </button>
            <button
              className="btn btn-outline"
              onClick={() => void handleRefreshGlobalSkills()}
              disabled={globalSkillsLoading || installLoading}
            >
              {globalSkillsLoading ? "刷新中..." : "刷新状态"}
            </button>
          </div>

          {globalSkillsActionMessage ? (
            <div className="rounded-md border border-border/70 bg-button-bg/60 px-2.5 py-2 text-fs-caption text-secondary-text">
              {globalSkillsActionMessage}
            </div>
          ) : null}

          {installResult ? (
            <pre className="max-h-[150px] overflow-auto rounded-md border border-border/70 bg-card-bg px-2 py-1.5 text-[11px] text-secondary-text whitespace-pre-wrap break-words">
{`${installResult.command}
${installResult.stdout || "(无标准输出)"}${installResult.stderr ? `
[stderr]
${installResult.stderr}` : ""}`}
            </pre>
          ) : null}
        </section>

        <section className="mt-3 flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div className="mb-1 flex flex-col gap-1 md:flex-row md:items-center md:justify-between">
            <div>
              <div className="text-[13px] font-semibold">技能启用矩阵</div>
              <div className="text-fs-caption text-secondary-text">左列固定技能；右列按 Agent 标记是否启用。</div>
            </div>
            <div className="text-fs-caption text-secondary-text">
              Skill {globalSkills.length} 个
              {globalSkillsQuery.trim() ? `，匹配 ${filteredGlobalSkills.length} 个` : ""}
            </div>
          </div>

          <input
            className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
            value={globalSkillsQuery}
            onChange={(event) => setGlobalSkillsQuery(event.target.value)}
            placeholder="搜索技能名 / 描述 / Agent / 路径"
            aria-label="搜索全局技能"
          />

          {globalSkillsError ? <div className="text-fs-caption text-error">读取失败：{globalSkillsError}</div> : null}

          {globalSkillsLoading ? (
            <div className="text-fs-caption text-secondary-text">读取中...</div>
          ) : filteredGlobalSkills.length === 0 ? (
            <div className="rounded-md border border-border/60 bg-button-bg/60 px-2.5 py-2 text-fs-caption text-secondary-text">
              未发现可展示的技能。
            </div>
          ) : (
            <SkillMatrixTable
              agents={agentColumns}
              skills={filteredGlobalSkills}
              actionCellKey={matrixActionKey}
              installLoading={installLoading}
              globalSkillsLoading={globalSkillsLoading}
              onCopySkillPath={handleCopySkillPath}
              onOpenSkillPath={handleOpenSkillPath}
              onToggleSkillAgent={handleToggleSkillAgent}
            />
          )}
        </section>
      </div>
    </div>
  );
}

type SkillMatrixTableProps = {
  agents: GlobalSkillAgent[];
  skills: GlobalSkillSummary[];
  actionCellKey: string | null;
  installLoading: boolean;
  globalSkillsLoading: boolean;
  onCopySkillPath: (path: string, name: string) => Promise<void>;
  onOpenSkillPath: (path: string, name: string) => Promise<void>;
  onToggleSkillAgent: (skill: GlobalSkillSummary, agent: GlobalSkillAgent, enabled: boolean) => Promise<void>;
};

type TruncatedTextWithTooltipProps = {
  value: string;
  wrapperClassName?: string;
  contentClassName?: string;
  onShowTooltip: (value: string, x: number, y: number) => void;
  onMoveTooltip: (x: number, y: number) => void;
  onHideTooltip: () => void;
};

function TruncatedTextWithTooltip({
  value,
  wrapperClassName,
  contentClassName,
  onShowTooltip,
  onMoveTooltip,
  onHideTooltip,
}: TruncatedTextWithTooltipProps) {
  return (
    <div
      className={`min-w-0 ${wrapperClassName ?? ""}`}
      onMouseEnter={(event) => onShowTooltip(value, event.clientX, event.clientY)}
      onMouseMove={(event) => onMoveTooltip(event.clientX, event.clientY)}
      onMouseLeave={onHideTooltip}
    >
      <div className={`overflow-hidden text-ellipsis whitespace-nowrap ${contentClassName ?? ""}`}>{value}</div>
    </div>
  );
}

function SkillMatrixTable({
  agents,
  skills,
  actionCellKey,
  installLoading,
  globalSkillsLoading,
  onCopySkillPath,
  onOpenSkillPath,
  onToggleSkillAgent,
}: SkillMatrixTableProps) {
  const [tooltip, setTooltip] = useState<{ text: string; x: number; y: number } | null>(null);

  const handleShowTooltip = useCallback((value: string, x: number, y: number) => {
    setTooltip({ text: value, x, y });
  }, []);

  const handleMoveTooltip = useCallback((x: number, y: number) => {
    setTooltip((previous) => (previous ? { ...previous, x, y } : previous));
  }, []);

  const handleHideTooltip = useCallback(() => {
    setTooltip(null);
  }, []);

  const tooltipStyle = useMemo(() => {
    if (!tooltip) {
      return undefined;
    }

    const viewportWidth = typeof window === "undefined" ? 1280 : window.innerWidth;
    const viewportHeight = typeof window === "undefined" ? 800 : window.innerHeight;
    const tooltipWidth = 520;
    const tooltipHeight = 260;
    const offsetX = 14;
    const offsetY = 18;

    return {
      left: Math.max(8, Math.min(tooltip.x + offsetX, viewportWidth - tooltipWidth - 8)),
      top: Math.max(8, Math.min(tooltip.y + offsetY, viewportHeight - tooltipHeight - 8)),
    };
  }, [tooltip]);

  return (
    <>
      <div className="max-h-[460px] overflow-auto rounded-lg border border-border/70">
        <table className="min-w-max border-collapse text-[12px]">
          <thead className="sticky top-0 z-20 bg-secondary-background">
            <tr>
              <th className="sticky left-0 z-30 w-[320px] max-w-[320px] border-b border-r border-border bg-secondary-background px-3 py-2 text-left font-semibold text-text">
                Skill
              </th>
              {agents.map((agent) => (
                <th
                  key={`skill-agent-head-${agent.id}`}
                  className="min-w-[120px] border-b border-border px-2 py-2 text-center font-semibold text-secondary-text"
                >
                  {agent.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {skills.map((skill) => {
              const enabledAgentIds = new Set(skill.agents.map((agent) => agent.id));
              const skillDescription = skill.description || "无描述";
              return (
                <tr key={`global-skill-row-${skill.name}`}>
                  <td className="sticky left-0 z-10 w-[320px] max-w-[320px] border-b border-r border-border bg-card-bg px-3 py-2 align-top">
                    <TruncatedTextWithTooltip
                      value={skill.name}
                      contentClassName="text-[13px] font-semibold text-text"
                      onShowTooltip={handleShowTooltip}
                      onMoveTooltip={handleMoveTooltip}
                      onHideTooltip={handleHideTooltip}
                    />
                    <TruncatedTextWithTooltip
                      value={skillDescription}
                      wrapperClassName="mt-0.5"
                      contentClassName="text-[11px] text-secondary-text"
                      onShowTooltip={handleShowTooltip}
                      onMoveTooltip={handleMoveTooltip}
                      onHideTooltip={handleHideTooltip}
                    />
                    <TruncatedTextWithTooltip
                      value={skill.canonicalPath}
                      wrapperClassName="mt-1"
                      contentClassName="text-[11px] text-secondary-text"
                      onShowTooltip={handleShowTooltip}
                      onMoveTooltip={handleMoveTooltip}
                      onHideTooltip={handleHideTooltip}
                    />
                    <div className="mt-2 flex items-center gap-1.5">
                      <button
                        className="btn btn-outline !px-2 !py-0.5 text-[11px]"
                        onClick={() => void onOpenSkillPath(skill.canonicalPath, skill.name)}
                      >
                        打开
                      </button>
                      <button
                        className="btn btn-outline !px-2 !py-0.5 text-[11px]"
                        onClick={() => void onCopySkillPath(skill.canonicalPath, skill.name)}
                      >
                        复制
                      </button>
                    </div>
                  </td>
                  {agents.map((agent) => {
                    const enabled = enabledAgentIds.has(agent.id);
                    const cellKey = `${skill.name}::${agent.id}`;
                    const cellActionLoading = actionCellKey === cellKey;
                    return (
                      <td
                        key={`global-skill-cell-${skill.name}-${agent.id}`}
                        className="border-b border-border px-2 py-2 text-center"
                      >
                        <button
                          className={`inline-flex min-w-[60px] items-center justify-center rounded-full border px-2 py-0.5 text-[11px] font-semibold transition-colors duration-150 ${
                            enabled
                              ? "border-[rgba(34,197,94,0.45)] bg-[rgba(34,197,94,0.18)] text-[rgb(22,163,74)] hover:bg-[rgba(34,197,94,0.28)]"
                              : "border-border bg-button-bg text-secondary-text hover:bg-button-hover"
                          }`}
                          title={enabled ? "点击卸载" : "点击安装"}
                          onClick={() => void onToggleSkillAgent(skill, agent, enabled)}
                          disabled={cellActionLoading || installLoading || globalSkillsLoading}
                        >
                          {cellActionLoading ? "处理中..." : enabled ? "启用" : "-"}
                        </button>
                      </td>
                    );
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {tooltip ? (
        <div
          className="pointer-events-none fixed z-[999] max-h-[260px] max-w-[520px] overflow-auto whitespace-normal break-words rounded-md border border-border bg-secondary-background px-2.5 py-2 text-[11px] leading-4 text-text shadow-lg"
          style={tooltipStyle}
        >
          {tooltip.text}
        </div>
      ) : null}
    </>
  );
}
