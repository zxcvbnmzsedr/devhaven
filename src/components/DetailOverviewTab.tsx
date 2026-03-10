import { memo } from "react";

import type { Project, TagData } from "../models/types";
import { swiftDateToJsDate } from "../models/types";
import { IconX } from "./Icons";

type TodoItem = {
  id: string;
  text: string;
  done: boolean;
};

export type DetailOverviewTabProps = {
  project: Project;
  projectTags: string[];
  availableTags: TagData[];
  getTagColor: (tag: string) => string;
  onAddTag: (tagName: string) => void;
  onRemoveTag: (tagName: string) => void;
  todoItems: TodoItem[];
  todoDraft: string;
  onTodoDraftChange: (value: string) => void;
  onAddTodo: () => void;
  onToggleTodo: (todoId: string, done: boolean) => void;
  onRemoveTodo: (todoId: string) => void;
};

const formatDate = (swiftDate: number) => {
  if (!swiftDate) {
    return "--";
  }
  const date = swiftDateToJsDate(swiftDate);
  return date.toLocaleString("zh-CN");
};

function DetailOverviewTab({
  project,
  projectTags,
  availableTags,
  getTagColor,
  onAddTag,
  onRemoveTag,
  todoItems,
  todoDraft,
  onTodoDraftChange,
  onAddTodo,
  onToggleTodo,
  onRemoveTodo,
}: DetailOverviewTabProps) {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
      <section className="flex flex-col gap-2.5">
        <div className="text-[14px] font-semibold">基础信息</div>
        <div className="grid grid-cols-[90px_1fr] gap-x-3 gap-y-1.5 text-fs-caption text-secondary-text">
          <div>最近修改</div>
          <div>{formatDate(project.mtime)}</div>
          <div>Git 提交</div>
          <div>{project.git_commits > 0 ? `${project.git_commits} 次` : "非 Git"}</div>
          <div>最后检查</div>
          <div>{formatDate(project.checked)}</div>
        </div>
      </section>

      <section className="flex flex-col gap-2.5">
        <div className="text-[14px] font-semibold">标签</div>
        <div className="flex flex-wrap gap-1.5">
          {projectTags.map((tag) => (
            <span
              key={tag}
              className="tag-pill"
              style={{ background: `${getTagColor(tag)}33`, color: getTagColor(tag) }}
            >
              {tag}
              <button
                className="ml-1.5 inline-flex items-center justify-center text-[12px] opacity-60 hover:opacity-100"
                onClick={() => onRemoveTag(tag)}
                aria-label={`移除标签 ${tag}`}
              >
                <IconX size={12} />
              </button>
            </span>
          ))}
        </div>
        {availableTags.length > 0 ? (
          <select
            className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
            onChange={(event) => {
              const value = event.target.value;
              if (value) {
                onAddTag(value);
              }
            }}
            defaultValue=""
          >
            <option value="">添加标签...</option>
            {availableTags.map((tag) => (
              <option key={tag.name} value={tag.name}>
                {tag.name}
              </option>
            ))}
          </select>
        ) : (
          <div className="text-fs-caption text-secondary-text">暂无可添加标签</div>
        )}
      </section>

      <section className="flex flex-col gap-2.5">
        <div className="text-[14px] font-semibold">Todo</div>
        <div className="flex items-center gap-2">
          <input
            className="flex-1 rounded-md border border-border bg-card-bg px-2 py-2 text-text"
            value={todoDraft}
            onChange={(event) => onTodoDraftChange(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                onAddTodo();
              }
            }}
            placeholder="输入待办并按回车添加"
          />
          <button className="btn" onClick={onAddTodo}>
            添加
          </button>
        </div>
        {todoItems.length === 0 ? (
          <div className="text-fs-caption text-secondary-text">暂无待办</div>
        ) : (
          <div className="flex flex-col gap-2">
            {todoItems.map((item) => (
              <label
                key={item.id}
                className="flex items-center gap-2 rounded-md border border-border bg-card-bg px-2.5 py-2"
              >
                <input
                  type="checkbox"
                  checked={item.done}
                  onChange={(event) => onToggleTodo(item.id, event.target.checked)}
                />
                <span className={`flex-1 text-[13px] ${item.done ? "text-secondary-text line-through" : "text-text"}`}>
                  {item.text}
                </span>
                <button
                  type="button"
                  className="icon-btn"
                  aria-label="删除待办"
                  onClick={(event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    onRemoveTodo(item.id);
                  }}
                >
                  <IconX size={12} />
                </button>
              </label>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

export default memo(DetailOverviewTab);
