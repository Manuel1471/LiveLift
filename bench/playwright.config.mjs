import {defineConfig} from "@playwright/test";
import {fileURLToPath} from "node:url";

const demo = fileURLToPath(new URL("../examples/demo/", import.meta.url));

export default defineConfig({
  testDir: "./e2e",
  workers: 1,
  retries: 0,
  reporter: "list",
  use: {baseURL: "http://127.0.0.1:4031"},
  projects: [
    {name: "chromium", use: {browserName: "chromium"}},
    {name: "firefox", use: {browserName: "firefox"}},
    {name: "webkit", use: {browserName: "webkit"}},
  ],
  webServer: {
    command: "mix assets.build && mix phx.server",
    cwd: demo,
    env: {PORT: "4031"},
    url: "http://127.0.0.1:4031/",
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
