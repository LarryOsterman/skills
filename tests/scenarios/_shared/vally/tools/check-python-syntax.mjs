// Validates syntax for generated Python files.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const EXCLUDED_DIRS = new Set([
  ".git",
  ".hg",
  ".svn",
  ".venv",
  "venv",
  "__pycache__",
  "node_modules",
  ".vally",
]);

function collectPythonFiles(dir, acc) {
  for (const entry of readdirSync(dir)) {
    if (entry.startsWith(".") && entry !== ".vally") continue;
    if (EXCLUDED_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      collectPythonFiles(full, acc);
    } else if (entry.endsWith(".py")) {
      acc.push(full);
    }
  }
}

const files = [];
collectPythonFiles(process.cwd(), files);

if (files.length === 0) {
  console.error("No Python files found to validate.");
  process.exit(1);
}

const failures = [];
for (const file of files) {
  const result = spawnSync("python", ["-m", "py_compile", file], {
    encoding: "utf-8",
  });
  if (result.status !== 0) {
    failures.push({ file, stderr: result.stderr?.trim() ?? "" });
  }
}

if (failures.length > 0) {
  console.error("Python syntax validation failed:");
  for (const failure of failures) {
    console.error(`- ${failure.file}`);
    if (failure.stderr) {
      console.error(failure.stderr);
    }
  }
  process.exit(1);
}

console.log(`Validated syntax for ${files.length} Python file(s).`);
