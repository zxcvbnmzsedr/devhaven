import { invokeCommand } from "../platform/commandClient";

/** 热应用 Web 服务配置（启停/地址/端口），无需重启整个应用。 */
export async function applyWebServerConfig(): Promise<void> {
  await invokeCommand("apply_web_server_config");
}
