import assert from "node:assert/strict";
import test from "node:test";

import {
  buildGitDailyAutoRefreshAttemptKey,
  pickGitDailyAutoRefreshPaths,
  shouldKeepActiveGitDailyRefreshJob,
  shouldReuseGitDailyRefreshJob,
} from "./gitDailyRefreshPolicy.ts";

test("shouldReuseGitDailyRefreshJob 沿用同一轮缺失数据补齐任务", () => {
  const current = {
    reason: "missing",
    signature: "missing:/repo-a|/repo-b|/repo-c",
    paths: ["/repo-a", "/repo-b", "/repo-c"],
  };
  const next = {
    reason: "missing",
    signature: "missing:/repo-b|/repo-c",
    paths: ["/repo-b", "/repo-c"],
  };

  assert.equal(shouldReuseGitDailyRefreshJob(current, next), true);
});

test("shouldReuseGitDailyRefreshJob 不会吞掉身份切换触发的全量刷新", () => {
  const current = {
    reason: "missing",
    signature: "missing:/repo-a|/repo-b",
    paths: ["/repo-a", "/repo-b"],
  };
  const next = {
    reason: "identity",
    signature: "identity:alice@example.com",
    paths: ["/repo-a", "/repo-b"],
  };

  assert.equal(shouldReuseGitDailyRefreshJob(current, next), false);
});

test("shouldReuseGitDailyRefreshJob 遇到新增路径时重启任务", () => {
  const current = {
    reason: "missing",
    signature: "missing:/repo-a|/repo-b",
    paths: ["/repo-a", "/repo-b"],
  };
  const next = {
    reason: "missing",
    signature: "missing:/repo-b|/repo-c",
    paths: ["/repo-b", "/repo-c"],
  };

  assert.equal(shouldReuseGitDailyRefreshJob(current, next), false);
});

test("pickGitDailyAutoRefreshPaths 只返回未尝试过的缺失项目", () => {
  const attempted = new Set([
    buildGitDailyAutoRefreshAttemptKey("/repo-b", "identity-a"),
  ]);
  const projects = [
    { path: "/repo-a", git_commits: 10, git_daily: null },
    { path: "/repo-b", git_commits: 5, git_daily: null },
    { path: "/repo-c", git_commits: 0, git_daily: null },
    { path: "/repo-d", git_commits: 3, git_daily: "2026-03-13:1" },
  ];

  assert.deepEqual(
    pickGitDailyAutoRefreshPaths(projects, "identity-a", attempted),
    ["/repo-a"],
  );
});

test("pickGitDailyAutoRefreshPaths 身份变化后允许同一路径重新自动统计一次", () => {
  const attempted = new Set([
    buildGitDailyAutoRefreshAttemptKey("/repo-a", "identity-a"),
  ]);
  const projects = [
    { path: "/repo-a", git_commits: 10, git_daily: null },
  ];

  assert.deepEqual(
    pickGitDailyAutoRefreshPaths(projects, "identity-b", attempted),
    ["/repo-a"],
  );
});


test("shouldKeepActiveGitDailyRefreshJob 不会让缺失数据副作用打断身份刷新", () => {
  const current = {
    reason: "identity",
    signature: "identity:alice@example.com",
    paths: ["/repo-a", "/repo-b"],
  };
  const next = {
    reason: "missing",
    signature: "missing:/repo-a",
    paths: ["/repo-a"],
  };

  assert.equal(shouldKeepActiveGitDailyRefreshJob(current, next), true);
});

test("shouldKeepActiveGitDailyRefreshJob 不会让空请求取消身份刷新", () => {
  const current = {
    reason: "identity",
    signature: "identity:alice@example.com",
    paths: ["/repo-a", "/repo-b"],
  };

  assert.equal(shouldKeepActiveGitDailyRefreshJob(current, null), true);
});
