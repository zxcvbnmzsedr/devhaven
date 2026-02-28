import { useCallback, useEffect, useMemo, useState, type Dispatch, type SetStateAction } from "react";

import type { CommandPaletteItem } from "../components/CommandPalette";
import { DATE_FILTER_OPTIONS, GIT_FILTER_OPTIONS, type DateFilter, type GitFilter } from "../models/filters";
import type { AppStateFile, Project } from "../models/types";
import { type CommandPaletteAction, resolveKeyboardEventTarget } from "../utils/worktreeHelpers";

type UseCommandPaletteParams = {
  showTerminalWorkspace: boolean;
  appState: AppStateFile;
  visibleProjects: Project[];
  setSelectedDirectory: Dispatch<SetStateAction<string | null>>;
  setSelectedTags: Dispatch<SetStateAction<Set<string>>>;
  setDateFilter: Dispatch<SetStateAction<DateFilter>>;
  setGitFilter: Dispatch<SetStateAction<GitFilter>>;
  setHeatmapFilteredProjectIds: Dispatch<SetStateAction<Set<string>>>;
  setHeatmapSelectedDateKey: Dispatch<SetStateAction<string | null>>;
  focusProject: (projectId: string) => void;
  handleOpenTerminal: (project: Project) => void;
  handleRunProjectScript: (projectId: string, scriptId: string) => Promise<void>;
};

export type UseCommandPaletteReturn = {
  isOpen: boolean;
  query: string;
  items: CommandPaletteItem[];
  activeIndex: number;
  onQueryChange: (value: string) => void;
  onActiveIndexChange: (index: number) => void;
  onSelectItem: (item: CommandPaletteItem) => void;
  onClose: () => void;
  openCommandPalette: () => void;
};

const EMPTY_COMMAND_PALETTE_ACTIONS: CommandPaletteAction[] = [];
const EMPTY_COMMAND_PALETTE_ITEMS: CommandPaletteItem[] = [];
const EMPTY_COMMAND_PALETTE_ACTION_MAP = new Map<string, CommandPaletteAction>();

/** 统一封装命令面板状态、快捷键监听与动作集合。 */
export function useCommandPalette({
  showTerminalWorkspace,
  appState,
  visibleProjects,
  setSelectedDirectory,
  setSelectedTags,
  setDateFilter,
  setGitFilter,
  setHeatmapFilteredProjectIds,
  setHeatmapSelectedDateKey,
  focusProject,
  handleOpenTerminal,
  handleRunProjectScript,
}: UseCommandPaletteParams): UseCommandPaletteReturn {
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [commandPaletteActiveIndex, setCommandPaletteActiveIndex] = useState(0);

  const openCommandPalette = useCallback(() => {
    if (showTerminalWorkspace) {
      return;
    }
    setCommandPaletteQuery("");
    setCommandPaletteActiveIndex(0);
    setIsCommandPaletteOpen(true);
  }, [showTerminalWorkspace]);

  const closeCommandPalette = useCallback(() => {
    setIsCommandPaletteOpen(false);
    setCommandPaletteQuery("");
    setCommandPaletteActiveIndex(0);
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const handleOpenCommandPalette = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() !== "k") {
        return;
      }
      if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) {
        return;
      }

      const activeTarget = resolveKeyboardEventTarget(event);
      if (activeTarget?.closest(".terminal-pane, .xterm, .xterm-helper-textarea")) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      if (!isCommandPaletteOpen) {
        openCommandPalette();
      }
    };

    window.addEventListener("keydown", handleOpenCommandPalette, true);
    return () => {
      window.removeEventListener("keydown", handleOpenCommandPalette, true);
    };
  }, [isCommandPaletteOpen, openCommandPalette]);

  useEffect(() => {
    if (isCommandPaletteOpen && showTerminalWorkspace) {
      closeCommandPalette();
    }
  }, [closeCommandPalette, isCommandPaletteOpen, showTerminalWorkspace]);

  const commandPaletteActions = useMemo<CommandPaletteAction[]>(() => {
    if (!isCommandPaletteOpen) {
      return EMPTY_COMMAND_PALETTE_ACTIONS;
    }

    const actions: CommandPaletteAction[] = [];
    const appendAction = (
      id: string,
      title: string,
      run: () => void,
      options?: { subtitle?: string; group?: string; keywords?: string[] },
    ) => {
      actions.push({
        id,
        title,
        subtitle: options?.subtitle,
        group: options?.group,
        searchText: [title, options?.subtitle ?? "", ...(options?.keywords ?? [])].join(" ").toLowerCase(),
        run,
      });
    };

    appendAction(
      "filter:clear-all",
      "清除全部筛选",
      () => {
        setSelectedDirectory(null);
        setSelectedTags(new Set());
        setDateFilter("all");
        setGitFilter("all");
        setHeatmapFilteredProjectIds(new Set());
        setHeatmapSelectedDateKey(null);
      },
      { group: "筛选", keywords: ["清空", "reset", "filter"] },
    );

    appendAction("filter:directory:all", "筛选目录：全部", () => setSelectedDirectory(null), {
      group: "筛选",
      keywords: ["directory", "目录", "all"],
    });
    for (const directory of appState.directories) {
      const name = directory.split("/").filter(Boolean).pop() ?? directory;
      appendAction(
        `filter:directory:${directory}`,
        `筛选目录：${name}`,
        () => setSelectedDirectory(directory),
        { group: "筛选", subtitle: directory, keywords: ["directory", "目录", name] },
      );
    }

    for (const option of DATE_FILTER_OPTIONS) {
      appendAction(
        `filter:date:${option.value}`,
        `日期筛选：${option.title}`,
        () => setDateFilter(option.value),
        { group: "筛选", keywords: ["date", "日期", option.shortLabel] },
      );
    }
    for (const option of GIT_FILTER_OPTIONS) {
      appendAction(
        `filter:git:${option.value}`,
        `Git 筛选：${option.title}`,
        () => setGitFilter(option.value),
        { group: "筛选", keywords: ["git", "筛选", option.title] },
      );
    }
    for (const tag of appState.tags) {
      if (tag.hidden) {
        continue;
      }
      appendAction(
        `filter:tag:${tag.name}`,
        `标签筛选：${tag.name}`,
        () => {
          setSelectedTags(new Set([tag.name]));
          setHeatmapFilteredProjectIds(new Set());
          setHeatmapSelectedDateKey(null);
        },
        { group: "筛选", keywords: ["tag", "标签", tag.name] },
      );
    }

    for (const project of visibleProjects) {
      appendAction(
        `project:focus:${project.id}`,
        `打开项目：${project.name}`,
        () => {
          focusProject(project.id);
        },
        { group: "项目", subtitle: project.path, keywords: ["open", "项目", project.name, project.path] },
      );
      appendAction(`project:terminal:${project.id}`, `打开终端：${project.name}`, () => handleOpenTerminal(project), {
        group: "终端",
        subtitle: project.path,
        keywords: ["terminal", "终端", project.name, project.path],
      });

      for (const script of project.scripts ?? []) {
        appendAction(
          `script:run:${project.id}:${script.id}`,
          `运行脚本：${script.name}`,
          () => {
            void handleRunProjectScript(project.id, script.id);
          },
          {
            group: "脚本",
            subtitle: `${project.name} · ${script.start}`,
            keywords: ["run", "script", "脚本", script.name, project.name, script.start],
          },
        );
      }
    }

    return actions;
  }, [
    appState.directories,
    appState.tags,
    focusProject,
    handleOpenTerminal,
    handleRunProjectScript,
    isCommandPaletteOpen,
    setDateFilter,
    setGitFilter,
    setHeatmapFilteredProjectIds,
    setHeatmapSelectedDateKey,
    setSelectedDirectory,
    setSelectedTags,
    visibleProjects,
  ]);

  const filteredCommandPaletteActions = useMemo(() => {
    if (!isCommandPaletteOpen) {
      return EMPTY_COMMAND_PALETTE_ACTIONS;
    }
    const normalizedQuery = commandPaletteQuery.trim().toLowerCase();
    if (!normalizedQuery) {
      return commandPaletteActions.slice(0, 200);
    }
    return commandPaletteActions.filter((action) => action.searchText.includes(normalizedQuery)).slice(0, 200);
  }, [commandPaletteActions, commandPaletteQuery, isCommandPaletteOpen]);

  const commandPaletteItems = useMemo<CommandPaletteItem[]>(
    () => {
      if (!isCommandPaletteOpen) {
        return EMPTY_COMMAND_PALETTE_ITEMS;
      }
      return filteredCommandPaletteActions.map((action) => ({
        id: action.id,
        title: action.title,
        subtitle: action.subtitle,
        group: action.group,
      }));
    },
    [filteredCommandPaletteActions, isCommandPaletteOpen],
  );

  const commandPaletteActionById = useMemo(() => {
    if (!isCommandPaletteOpen) {
      return EMPTY_COMMAND_PALETTE_ACTION_MAP;
    }
    return new Map(filteredCommandPaletteActions.map((action) => [action.id, action]));
  }, [filteredCommandPaletteActions, isCommandPaletteOpen]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    setCommandPaletteActiveIndex(0);
  }, [commandPaletteQuery, isCommandPaletteOpen]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    setCommandPaletteActiveIndex((prev) => {
      if (commandPaletteItems.length === 0) {
        return 0;
      }
      if (prev < 0 || prev >= commandPaletteItems.length) {
        return 0;
      }
      return prev;
    });
  }, [commandPaletteItems.length, isCommandPaletteOpen]);

  const handleSelectCommandPaletteItem = useCallback(
    (item: CommandPaletteItem) => {
      const action = commandPaletteActionById.get(item.id);
      if (!action) {
        return;
      }
      action.run();
      closeCommandPalette();
    },
    [closeCommandPalette, commandPaletteActionById],
  );

  return {
    isOpen: isCommandPaletteOpen,
    query: commandPaletteQuery,
    items: commandPaletteItems,
    activeIndex: commandPaletteActiveIndex,
    onQueryChange: setCommandPaletteQuery,
    onActiveIndexChange: setCommandPaletteActiveIndex,
    onSelectItem: handleSelectCommandPaletteItem,
    onClose: closeCommandPalette,
    openCommandPalette,
  };
}
