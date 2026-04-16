import AddConfigurationMenu from "./AddConfigurationMenu";
import { Placeholder } from "./Fields";

export default function ConfigurationSidebar({
  payload,
  onAddConfiguration,
  onSelectConfiguration,
}) {
  return (
    <aside className="left-panel">
      <div className="left-panel-header">
        <div className="left-panel-copy">
          <div className="panel-title">项目运行配置</div>
          <div className="panel-subtitle">
            {payload.configurations.length} 个配置
          </div>
        </div>
        <AddConfigurationMenu
          availableKinds={payload.availableKinds}
          onAdd={onAddConfiguration}
        />
      </div>

      <div className="configuration-list">
        {payload.configurations.length === 0 ? (
          <Placeholder text="暂无运行配置，点击右上角新增。" />
        ) : (
          payload.configurations.map((configuration) => {
            const isSelected =
              configuration.id === payload.selectedConfigurationID;

            return (
              <button
                key={configuration.id}
                type="button"
                className={`configuration-row${isSelected ? " selected" : ""}`}
                onClick={() => onSelectConfiguration(configuration.id)}
              >
                <div className="configuration-name">
                  {configuration.resolvedName}
                </div>
                <div className="configuration-kind">
                  {configuration.kindTitle}
                </div>
                <div className="configuration-summary mono">
                  {configuration.rowSummary}
                </div>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}
