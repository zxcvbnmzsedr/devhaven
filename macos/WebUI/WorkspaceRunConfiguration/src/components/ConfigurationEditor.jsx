import SectionCard from "./SectionCard";
import { Placeholder, TextField, ToggleField } from "./Fields";

function CustomShellEditor({ configuration, onUpdateStringField }) {
  return (
    <SectionCard
      title="Shell Script"
      description="与 IDEA 的 Shell Script 配置类似，这里只保留最核心的命令输入。"
    >
      <label className="labeled-field">
        <span className="field-label">Shell 命令</span>
        <textarea
          value={configuration.customCommand || ""}
          onChange={(event) =>
            onUpdateStringField(
              configuration.id,
              "customCommand",
              event.target.value
            )
          }
        />
      </label>
    </SectionCard>
  );
}

function RemoteLogEditor({
  configuration,
  onUpdateStringField,
  onUpdateBooleanField,
}) {
  return (
    <>
      <SectionCard
        title="连接设置"
        description="先填写目标主机、SSH 用户、端口与私钥。"
      >
        <div className="paired-grid">
          <TextField
            label="服务器 *"
            value={configuration.remoteServer}
            placeholder="例如：root@192.168.0.131"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remoteServer", value)
            }
          />
          <TextField
            label="SSH 用户"
            value={configuration.remoteUser}
            placeholder="可留空"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remoteUser", value)
            }
          />
          <TextField
            label="端口"
            value={configuration.remotePort}
            placeholder="22"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remotePort", value)
            }
          />
          <TextField
            label="私钥文件"
            value={configuration.remoteIdentityFile}
            placeholder="~/.ssh/id_ed25519"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remoteIdentityFile", value)
            }
          />
        </div>
      </SectionCard>

      <SectionCard
        title="日志设置"
        description="决定查看哪个文件、读取多少行，以及是否持续 follow。"
      >
        <div className="paired-grid">
          <TextField
            label="日志路径 *"
            value={configuration.remoteLogPath}
            placeholder="/var/log/app.log"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remoteLogPath", value)
            }
          />
          <TextField
            label="输出行数"
            value={configuration.remoteLines}
            placeholder="200"
            onChange={(value) =>
              onUpdateStringField(configuration.id, "remoteLines", value)
            }
          />
        </div>

        <ToggleField
          label="持续跟踪（follow）"
          checked={configuration.remoteFollow}
          onChange={(value) =>
            onUpdateBooleanField(configuration.id, "remoteFollow", value)
          }
        />
      </SectionCard>

      <SectionCard
        title="安全设置"
        description="控制 host key 校验与是否允许 SSH 密码交互。"
      >
        <div className="paired-grid">
          <TextField
            label="StrictHostKeyChecking"
            value={configuration.remoteStrictHostKeyChecking}
            placeholder="accept-new"
            onChange={(value) =>
              onUpdateStringField(
                configuration.id,
                "remoteStrictHostKeyChecking",
                value
              )
            }
          />
        </div>

        <ToggleField
          label="允许密码交互（关闭 BatchMode）"
          checked={configuration.remoteAllowPasswordPrompt}
          onChange={(value) =>
            onUpdateBooleanField(
              configuration.id,
              "remoteAllowPasswordPrompt",
              value
            )
          }
        />
      </SectionCard>
    </>
  );
}

export default function ConfigurationEditor({
  payload,
  selectedConfiguration,
  onUpdateStringField,
  onUpdateBooleanField,
  onRequestDuplicate,
  onRequestDelete,
}) {
  if (!selectedConfiguration) {
    return (
      <main className="right-panel">
        <Placeholder
          text="请选择一个运行配置开始编辑。"
          className="right-placeholder"
        />
      </main>
    );
  }

  return (
    <main className="right-panel">
      <div className="editor-card">
        <div className="editor-header">
          <div className="editor-header-copy">
            <div className="editor-title">
              {selectedConfiguration.resolvedName}
            </div>
            <div className="editor-meta">
              <span className="type-badge">
                {selectedConfiguration.kindTitle}
              </span>
              <span className="config-id mono">
                配置 ID：{selectedConfiguration.id}
              </span>
            </div>
          </div>

          <div className="header-actions">
            <button
              type="button"
              className="button button-bordered"
              onClick={() => onRequestDuplicate(selectedConfiguration.id)}
            >
              复制当前配置
            </button>
            <button
              type="button"
              className="button button-bordered button-destructive"
              onClick={() => onRequestDelete(selectedConfiguration.id)}
            >
              删除当前配置
            </button>
          </div>
        </div>

        <SectionCard
          title="基础信息"
          description="类型在创建时就确定；如果选错了，建议直接复制当前配置后重建。"
        >
          <TextField
            label="名称（可留空，保存时自动生成）"
            value={selectedConfiguration.name}
            placeholder={selectedConfiguration.suggestedName}
            onChange={(value) =>
              onUpdateStringField(selectedConfiguration.id, "name", value)
            }
          />

          <div className="suggestion-row">
            <span className="field-label">建议名称：</span>
            <span className="mono selectable">
              {selectedConfiguration.suggestedName}
            </span>
          </div>
        </SectionCard>

        {selectedConfiguration.kind === "customShell" ? (
          <CustomShellEditor
            configuration={selectedConfiguration}
            onUpdateStringField={onUpdateStringField}
          />
        ) : (
          <RemoteLogEditor
            configuration={selectedConfiguration}
            onUpdateStringField={onUpdateStringField}
            onUpdateBooleanField={onUpdateBooleanField}
          />
        )}

        <SectionCard
          title="命令预览"
          description="只读预览最终会交给执行器的命令，避免用户必须先点 Run 才知道发生了什么。"
        >
          <pre className="preview mono selectable">
            {selectedConfiguration.commandPreview}
          </pre>
        </SectionCard>

        {payload.validationMessage ? (
          <div className="validation-message">
            {payload.validationMessage}
          </div>
        ) : null}
      </div>
    </main>
  );
}
