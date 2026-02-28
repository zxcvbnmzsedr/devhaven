export type GitDailyMap = Record<string, number>;

const GIT_DAILY_PARSE_CACHE_LIMIT = 200;
const gitDailyParseCache = new Map<string, GitDailyMap>();

function cloneGitDailyMap(data: GitDailyMap): GitDailyMap {
  return { ...data };
}

function cacheGitDailyParseResult(key: string, value: GitDailyMap): void {
  gitDailyParseCache.set(key, value);
  if (gitDailyParseCache.size <= GIT_DAILY_PARSE_CACHE_LIMIT) {
    return;
  }
  const oldestKey = gitDailyParseCache.keys().next().value;
  if (oldestKey !== undefined) {
    gitDailyParseCache.delete(oldestKey);
  }
}

export function parseGitDaily(gitDaily?: string | null): GitDailyMap {
  if (!gitDaily) {
    return {};
  }
  const trimmed = gitDaily.trim();
  if (!trimmed) {
    return {};
  }
  const cached = gitDailyParseCache.get(trimmed);
  if (cached) {
    gitDailyParseCache.delete(trimmed);
    gitDailyParseCache.set(trimmed, cached);
    return cloneGitDailyMap(cached);
  }
  const result: GitDailyMap = {};
  const entries = trimmed.split(",");
  for (const entry of entries) {
    const [date, countRaw] = entry.split(":");
    if (!date || !countRaw) {
      continue;
    }
    const count = Number.parseInt(countRaw, 10);
    if (!Number.isFinite(count)) {
      continue;
    }
    result[date] = count;
  }
  cacheGitDailyParseResult(trimmed, result);
  return cloneGitDailyMap(result);
}

export function formatGitDaily(data: GitDailyMap): string {
  return Object.keys(data)
    .sort()
    .map((date) => `${date}:${data[date]}`)
    .join(",");
}

export function getCommitCountFromGitDaily(gitDaily: string | null | undefined, date: Date): number {
  const map = parseGitDaily(gitDaily);
  const dateString = formatDateKey(date);
  return map[dateString] ?? 0;
}

export function formatDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}
