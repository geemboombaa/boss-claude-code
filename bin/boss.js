#!/usr/bin/env node
"use strict";
const { execFileSync, spawnSync } = require("child_process");
const os = require("os");
const path = require("path");
const fs = require("fs");

const scriptDir = path.join(__dirname, "..");
const args = process.argv.slice(2);
const command = args[0] || "install";

if (command !== "install") {
  console.error(`Unknown command: ${command}`);
  process.exit(1);
}

const passArgs = args.slice(1);

if (os.platform() === "win32") {
  const ps1 = path.join(scriptDir, "install.ps1");
  const result = spawnSync(
    "powershell",
    ["-ExecutionPolicy", "Bypass", "-File", ps1, ...passArgs],
    { stdio: "inherit" }
  );
  process.exit(result.status || 0);
} else {
  const sh = path.join(scriptDir, "install.sh");
  fs.chmodSync(sh, "755");
  const result = spawnSync("bash", [sh, ...passArgs], { stdio: "inherit" });
  process.exit(result.status || 0);
}
