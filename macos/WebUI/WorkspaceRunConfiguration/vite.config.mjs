import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writeFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const projectDir = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(
  projectDir,
  "../../Sources/DevHavenApp/WorkspaceRunConfigurationResources"
);
const entry = resolve(projectDir, "src/main.jsx");

function writeWKWebViewIndexPlugin() {
  return {
    name: "write-wkwebview-index",
    writeBundle() {
      writeFileSync(
        resolve(outDir, "index.html"),
        `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Run Configuration Editor</title>
    <link rel="stylesheet" href="./assets/run-configuration-sheet.css" />
  </head>
  <body>
    <div id="app"></div>
    <script src="./assets/run-configuration-sheet.js"></script>
  </body>
</html>
`
      );
    },
  };
}

export default defineConfig({
  base: "./",
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  plugins: [react(), writeWKWebViewIndexPlugin()],
  publicDir: false,
  build: {
    outDir,
    emptyOutDir: true,
    sourcemap: false,
    target: "es2022",
    cssCodeSplit: false,
    lib: {
      entry,
      name: "DevHavenRunConfigurationSheet",
      formats: ["iife"],
      fileName: () => "assets/run-configuration-sheet.js",
    },
    rollupOptions: {
      output: {
        assetFileNames(assetInfo) {
          if (assetInfo.name?.endsWith(".css")) {
            return "assets/run-configuration-sheet.css";
          }
          return "assets/[name][extname]";
        },
      },
    },
  },
});
