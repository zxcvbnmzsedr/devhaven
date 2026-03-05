import { getAppVersionRuntime } from "../platform/runtime";

const RELEASES_URL = "https://api.github.com/repos/zxcvbnmzsedr/devhaven/releases/latest";

type ReleaseResponse = {
  tag_name?: string;
  name?: string;
  html_url?: string;
};

export type UpdateCheckResult =
  | { status: "latest"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "update"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "error"; currentVersion: string; message: string };

/** 检查是否有新版本发布。 */
export async function checkForUpdates(): Promise<UpdateCheckResult> {
  const currentVersion = await getAppVersionRuntime();
  try {
    const response = await fetch(RELEASES_URL, {
      headers: {
        Accept: "application/vnd.github+json",
      },
    });
    if (!response.ok) {
      return {
        status: "error",
        currentVersion,
        message: `更新服务返回异常（${response.status}）`,
      };
    }
    const payload = (await response.json()) as ReleaseResponse;
    const latestRaw = payload.tag_name ?? payload.name ?? "";
    const latestVersion = normalizeVersion(latestRaw);
    if (!latestVersion) {
      return {
        status: "error",
        currentVersion,
        message: "未获取到版本信息",
      };
    }
    const normalizedCurrent = normalizeVersion(currentVersion);
    const isUpdate = compareVersions(latestVersion, normalizedCurrent) > 0;
    return {
      status: isUpdate ? "update" : "latest",
      currentVersion,
      latestVersion,
      url: payload.html_url,
    };
  } catch (error) {
    return {
      status: "error",
      currentVersion,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

function normalizeVersion(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }
  const sanitized = trimmed.startsWith("v") ? trimmed.slice(1) : trimmed;
  const match = sanitized.match(/\d+(?:\.\d+){0,2}/);
  return match ? match[0] : sanitized;
}

function compareVersions(left: string, right: string): number {
  const leftParts = parseVersionParts(left);
  const rightParts = parseVersionParts(right);
  const maxLength = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < maxLength; index += 1) {
    const leftValue = leftParts[index] ?? 0;
    const rightValue = rightParts[index] ?? 0;
    if (leftValue > rightValue) {
      return 1;
    }
    if (leftValue < rightValue) {
      return -1;
    }
  }
  return 0;
}

function parseVersionParts(value: string): number[] {
  if (!value) {
    return [];
  }
  return value
    .split(".")
    .map((part) => Number.parseInt(part, 10))
    .filter((part) => Number.isFinite(part));
}
