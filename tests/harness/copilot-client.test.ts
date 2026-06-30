import { describe, expect, it } from "vitest";

import { SkillCopilotClient } from "./copilot-client.js";

describe("SkillCopilotClient.extractCode", () => {
  it("keeps assignment line for multiline constructor call without fences", () => {
    const client = new SkillCopilotClient(process.cwd(), true);

    const response = [
      "from azure.identity import DefaultAzureCredential",
      "from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter",
      "",
      "exporter = AzureMonitorTraceExporter(",
      "    credential=DefaultAzureCredential(),",
      '    storage_directory="/path/to/storage",',
      "    disable_offline_storage=False,",
      ")",
    ].join("\n");

    const extracted = (
      client as unknown as { extractCode: (r: string) => string }
    ).extractCode(response);

    expect(extracted).toContain("exporter = AzureMonitorTraceExporter(");
    expect(extracted).toContain("disable_offline_storage=False,");
    expect(extracted.trim().endsWith(")")).toBe(true);
  });

  it("prefers fenced code blocks when present", () => {
    const client = new SkillCopilotClient(process.cwd(), true);

    const response = [
      "Here is the implementation:",
      "```python",
      "x = 1",
      "print(x)",
      "```",
    ].join("\n");

    const extracted = (
      client as unknown as { extractCode: (r: string) => string }
    ).extractCode(response);

    expect(extracted).toBe("x = 1\nprint(x)");
  });
});
