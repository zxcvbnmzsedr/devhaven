import { invokeCommand } from "../platform/commandClient";

import type { HeatmapCacheFile } from "../models/heatmap";

export async function loadHeatmapCache(): Promise<HeatmapCacheFile> {
  return invokeCommand<HeatmapCacheFile>("load_heatmap_cache");
}

export async function saveHeatmapCache(cache: HeatmapCacheFile): Promise<void> {
  await invokeCommand("save_heatmap_cache", { cache });
}
