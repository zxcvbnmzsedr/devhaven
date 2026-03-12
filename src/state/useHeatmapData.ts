import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { HeatmapCacheEntry, HeatmapCacheFile, HeatmapData } from "../models/heatmap";
import { EMPTY_HEATMAP_CACHE } from "../models/heatmap";
import type { DailyActivity, HeatmapStats } from "../models/dashboard";
import type { GitIdentity, Project } from "../models/types";
import { loadHeatmapCache, saveHeatmapCache } from "../services/heatmap";
import { buildGitIdentitySignature } from "../utils/gitIdentity";
import { formatDateKey, parseGitDaily } from "../utils/gitDaily";

const REFRESH_INTERVAL_MS = 30 * 60 * 1000;

export type HeatmapStore = {
  cache: HeatmapCacheFile;
  isLoading: boolean;
  error: string | null;
  refresh: (force?: boolean) => Promise<void>;
  getHeatmapData: (days: number) => HeatmapData[];
  getDailyActivities: (days: number) => DailyActivity[];
  getStats: (days: number) => HeatmapStats;
};

/** 热力图数据仓库，负责缓存与聚合计算。 */
export function useHeatmapData(projects: Project[], gitIdentities: GitIdentity[]): HeatmapStore {
  const [cache, setCache] = useState<HeatmapCacheFile>(EMPTY_HEATMAP_CACHE);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const cacheRef = useRef<HeatmapCacheFile>(EMPTY_HEATMAP_CACHE);
  const hasLoadedCacheRef = useRef(false);
  const projectsRef = useRef(projects);
  projectsRef.current = projects;
  const gitDailySignature = useMemo(
    () => buildGitDailySignature(projects, gitIdentities),
    [gitIdentities, projects],
  );
  const gitDailySignatureRef = useRef(gitDailySignature);
  gitDailySignatureRef.current = gitDailySignature;

  const syncCache = useCallback(async (nextProjects: Project[], nextSignature: string, force?: boolean) => {
    setIsLoading(true);
    setError(null);
    try {
      let workingCache = cacheRef.current;
      if (!hasLoadedCacheRef.current) {
        workingCache = await loadHeatmapCache().catch(() => EMPTY_HEATMAP_CACHE);
        hasLoadedCacheRef.current = true;
      }
      const shouldRebuild = shouldRefreshCache(workingCache, nextProjects, nextSignature, force);
      if (shouldRebuild) {
        const rebuilt = buildHeatmapCache(nextProjects, nextSignature);
        cacheRef.current = rebuilt;
        setCache(rebuilt);
        await saveHeatmapCache(rebuilt);
      } else {
        cacheRef.current = workingCache;
        setCache(workingCache);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setIsLoading(false);
    }
  }, []);

  const refresh = useCallback(
    async (force?: boolean) => {
      await syncCache(projectsRef.current, gitDailySignatureRef.current, force);
    },
    [syncCache],
  );

  useEffect(() => {
    void syncCache(projectsRef.current, gitDailySignature, false);
  }, [gitDailySignature, projects.length, syncCache]);

  const getHeatmapData = useCallback(
    (days: number) => buildHeatmapData(cache, days),
    [cache],
  );

  const getDailyActivities = useCallback(
    (days: number) => buildDailyActivities(cache, days),
    [cache],
  );

  const getStats = useCallback(
    (days: number) => buildHeatmapStats(getHeatmapData(days)),
    [getHeatmapData],
  );

  return useMemo(
    () => ({
      cache,
      isLoading,
      error,
      refresh,
      getHeatmapData,
      getDailyActivities,
      getStats,
    }),
    [cache, isLoading, error, refresh, getHeatmapData, getDailyActivities, getStats],
  );
}

function shouldRefreshCache(
  cache: HeatmapCacheFile,
  projects: Project[],
  gitDailySignature: string,
  force?: boolean,
) {
  if (force) {
    return true;
  }
  if (!cache.lastUpdated) {
    return true;
  }
  const lastUpdated = Date.parse(cache.lastUpdated);
  if (!Number.isFinite(lastUpdated)) {
    return true;
  }
  if (cache.projectCount !== projects.length) {
    return true;
  }
  if (cache.gitDailySignature !== gitDailySignature) {
    return true;
  }
  return Date.now() - lastUpdated > REFRESH_INTERVAL_MS;
}

function buildHeatmapCache(projects: Project[], gitDailySignature: string): HeatmapCacheFile {
  const dailyActivity: Record<string, HeatmapCacheEntry> = {};

  for (const project of projects) {
    if (!project.git_daily) {
      continue;
    }
    const map = parseGitDaily(project.git_daily);
    for (const [dateString, count] of Object.entries(map)) {
      if (!dailyActivity[dateString]) {
        dailyActivity[dateString] = {
          dateString,
          commitCount: 0,
          projectIds: [],
        };
      }
      const entry = dailyActivity[dateString];
      entry.commitCount += count;
      if (!entry.projectIds.includes(project.id)) {
        entry.projectIds.push(project.id);
      }
    }
  }

  return {
    version: 1,
    lastUpdated: new Date().toISOString(),
    dailyActivity,
    projectCount: projects.length,
    gitDailySignature,
  };
}

function buildHeatmapData(cache: HeatmapCacheFile, days: number): HeatmapData[] {
  const normalizedDays = Math.max(1, Math.floor(days));
  const endDate = startOfDay(new Date());
  const startDate = new Date(endDate);
  startDate.setDate(endDate.getDate() - (normalizedDays - 1));

  const results: HeatmapData[] = [];
  const counts: number[] = [];

  for (let offset = 0; offset < normalizedDays; offset += 1) {
    const date = new Date(startDate);
    date.setDate(startDate.getDate() + offset);
    const key = formatDateKey(date);
    const entry = cache.dailyActivity[key];
    const commitCount = entry?.commitCount ?? 0;
    counts.push(commitCount);
    results.push({
      date,
      commitCount,
      projectIds: entry?.projectIds ?? [],
      intensity: 0,
    });
  }

  const maxCount = Math.max(...counts, 0);
  return results.map((item) => ({
    ...item,
    intensity: calculateIntensity(item.commitCount, maxCount),
  }));
}

function calculateIntensity(count: number, maxCount: number) {
  if (count <= 0 || maxCount <= 0) {
    return 0;
  }
  const ratio = count / maxCount;
  const level = Math.ceil(ratio * 4);
  return Math.max(1, Math.min(4, level));
}

function buildDailyActivities(cache: HeatmapCacheFile, days: number): DailyActivity[] {
  return buildHeatmapData(cache, days)
    .filter((item) => item.commitCount > 0)
    .map((item) => ({
      id: formatDateKey(item.date),
      date: item.date,
      commitCount: item.commitCount,
      projectIds: item.projectIds,
    }))
    .sort((a, b) => b.date.getTime() - a.date.getTime());
}

function buildHeatmapStats(data: HeatmapData[]): HeatmapStats {
  const totalDays = data.length;
  const activeDays = data.filter((item) => item.commitCount > 0).length;
  const totalCommits = data.reduce((sum, item) => sum + item.commitCount, 0);
  const maxCommitsInDay = data.reduce((max, item) => Math.max(max, item.commitCount), 0);
  const averageCommitsPerDay = totalDays === 0 ? 0 : totalCommits / totalDays;
  const activityRate = totalDays === 0 ? 0 : activeDays / totalDays;

  return {
    totalDays,
    activeDays,
    totalCommits,
    maxCommitsInDay,
    averageCommitsPerDay,
    activityRate,
  };
}

function startOfDay(date: Date) {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function buildGitDailySignature(projects: Project[], gitIdentities: GitIdentity[]) {
  const identitySignature = buildGitIdentitySignature(gitIdentities);
  const entries = projects
    .map((project) => `${project.id}:${project.git_daily ?? ""}`)
    .sort();
  entries.push(`identities:${identitySignature}`);
  let hash = 0;
  for (const entry of entries) {
    for (let index = 0; index < entry.length; index += 1) {
      hash = (hash * 31 + entry.charCodeAt(index)) | 0;
    }
  }
  return String(hash);
}
