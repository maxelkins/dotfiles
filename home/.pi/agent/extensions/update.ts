import {
  BorderedLoader,
  type ExecResult,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

type UpdateRunResult =
  | { kind: "completed"; result: ExecResult }
  | { kind: "cancelled" }
  | { kind: "failed"; message: string };

const parseNodeVersion = (value: string): number[] | undefined => {
  const match = value.trim().match(/^v?(\d+)\.(\d+)\.(\d+)$/);
  return match ? match.slice(1).map(Number) : undefined;
};

const isNewerVersion = (candidate: string, current: string): boolean => {
  const candidateParts = parseNodeVersion(candidate);
  const currentParts = parseNodeVersion(current);
  if (!candidateParts || !currentParts) return false;

  for (let index = 0; index < candidateParts.length; index += 1) {
    if (candidateParts[index] !== currentParts[index]) {
      return candidateParts[index] > currentParts[index];
    }
  }
  return false;
};

export default function (pi: ExtensionAPI) {
  pi.registerCommand("update", {
    description: "Update the Pi runtime, Pi, and installed extensions",
    handler: async (_args, ctx) => {
      const runtimeDir = join(homedir(), ".config", "pi-runtime");
      const toolVersionsPath = join(runtimeDir, ".tool-versions");

      const getPiVersion = async (): Promise<string | undefined> => {
        const result = await pi.exec("pi", ["--version"]);
        return result.code === 0
          ? result.stdout.trim() || undefined
          : undefined;
      };

      const getConfiguredNodeVersion = async (): Promise<
        string | undefined
      > => {
        try {
          const contents = await readFile(toolVersionsPath, "utf8");
          return contents.match(/^nodejs\s+(\S+)/m)?.[1];
        } catch {
          return undefined;
        }
      };

      const getInstalledPackageVersions = async (): Promise<
        Map<string, string>
      > => {
        const versions = new Map<string, string>();
        const result = await pi.exec("pi", ["list"]);
        if (result.code !== 0) return versions;

        let source: string | undefined;
        for (const line of result.stdout.split("\n")) {
          if (/^  \S/.test(line) && !/^    /.test(line)) {
            source = line.trim().replace(/ \(filtered\)$/, "");
            continue;
          }

          const pathMatch = line.match(/^    (.+)$/);
          if (!source || !pathMatch) continue;

          const installedPath = pathMatch[1].trim();
          let version: string | undefined;
          if (source.startsWith("npm:")) {
            try {
              const manifest = JSON.parse(
                await readFile(join(installedPath, "package.json"), "utf8"),
              ) as {
                version?: string;
              };
              version = manifest.version;
            } catch {
              // Missing or invalid package metadata is ignored.
            }
          } else {
            const git = await pi.exec("git", [
              "-C",
              installedPath,
              "rev-parse",
              "HEAD",
            ]);
            if (git.code === 0) version = git.stdout.trim() || undefined;
          }

          if (version) versions.set(`${source}\0${installedPath}`, version);
        }

        return versions;
      };

      const runUpdate = async (
        command: string,
        args: string[],
        message: string,
        cwd?: string,
      ): Promise<UpdateRunResult> => {
        ctx.ui.setStatus("update", message);

        if (ctx.mode !== "tui") {
          try {
            return {
              kind: "completed",
              result: await pi.exec(command, args, { cwd }),
            };
          } catch (error) {
            return {
              kind: "failed",
              message: error instanceof Error ? error.message : String(error),
            };
          }
        }

        return ctx.ui.custom<UpdateRunResult>(
          (tui, theme, _keybindings, done) => {
            const loader = new BorderedLoader(tui, theme, message);
            let settled = false;
            const finish = (result: UpdateRunResult) => {
              if (settled) return;
              settled = true;
              done(result);
            };

            loader.onAbort = () => finish({ kind: "cancelled" });
            pi.exec(command, args, { cwd, signal: loader.signal })
              .then((result) => finish({ kind: "completed", result }))
              .catch((error) =>
                finish({
                  kind: "failed",
                  message:
                    error instanceof Error ? error.message : String(error),
                }),
              );

            return loader;
          },
        );
      };

      const requireUpdate = async (
        command: string,
        args: string[],
        message: string,
        cwd?: string,
      ): Promise<ExecResult | undefined> => {
        const update = await runUpdate(command, args, message, cwd);
        if (update.kind === "cancelled") {
          ctx.ui.notify("Update cancelled.", "info");
          return undefined;
        }
        if (update.kind === "failed" || update.result.code !== 0) {
          const failure =
            update.kind === "failed"
              ? update.message
              : update.result.stderr ||
                update.result.stdout ||
                `${message} failed`;
          ctx.ui.notify(failure, "error");
          return undefined;
        }
        return update.result;
      };

      let reloading = false;
      try {
        ctx.ui.setStatus("update", "Checking installed versions...");
        const piVersionBefore = await getPiVersion();
        const packageVersionsBefore = await getInstalledPackageVersions();
        const nodeVersionBefore = await getConfiguredNodeVersion();
        let nodeVersionAfter = nodeVersionBefore;
        let nodeUpdated = false;

        if (nodeVersionBefore && parseNodeVersion(nodeVersionBefore)) {
          const nodeMajor = parseNodeVersion(nodeVersionBefore)?.[0];
          const latest = await pi.exec(
            "asdf",
            ["latest", "nodejs", String(nodeMajor)],
            { cwd: runtimeDir },
          );
          const latestVersion = latest.stdout.trim();

          if (
            latest.code === 0 &&
            isNewerVersion(latestVersion, nodeVersionBefore) &&
            ctx.hasUI
          ) {
            const updateNode = await ctx.ui.confirm(
              "Update Pi's Node runtime?",
              `${nodeVersionBefore} -> ${latestVersion}\n\nThis updates the tracked pi-runtime/.tool-versions file.`,
            );

            if (updateNode) {
              const installed = await requireUpdate(
                "asdf",
                ["install", "nodejs", latestVersion],
                `Installing Node ${latestVersion}...`,
                runtimeDir,
              );
              if (!installed) return;

              const nodeDirResult = await requireUpdate(
                "asdf",
                ["where", "nodejs", latestVersion],
                "Resolving the new Node runtime...",
                runtimeDir,
              );
              if (!nodeDirResult) return;

              const nodeDir = nodeDirResult.stdout.trim();
              const nodeBin = join(nodeDir, "bin", "node");
              const npmCli = join(
                nodeDir,
                "lib",
                "node_modules",
                "npm",
                "bin",
                "npm-cli.js",
              );
              const piInstalled = await requireUpdate(
                nodeBin,
                [
                  npmCli,
                  "install",
                  "-g",
                  "--ignore-scripts",
                  "--min-release-age=0",
                  "--no-fund",
                  "--no-audit",
                  "@earendil-works/pi-coding-agent",
                ],
                `Installing Pi for Node ${latestVersion}...`,
                runtimeDir,
              );
              if (!piInstalled) return;

              const reshimmed = await requireUpdate(
                "asdf",
                ["reshim", "nodejs", latestVersion],
                "Refreshing asdf shims...",
                runtimeDir,
              );
              if (!reshimmed) return;

              const configured = await requireUpdate(
                "asdf",
                ["set", "nodejs", latestVersion],
                "Updating Pi's Node configuration...",
                runtimeDir,
              );
              if (!configured) return;

              nodeVersionAfter = latestVersion;
              nodeUpdated = true;
            }
          }
        }

        if (!nodeUpdated) {
          const self = await requireUpdate(
            "pi",
            ["update"],
            "Updating Pi...",
          );
          if (!self) return;
        }

        const extensions = await requireUpdate(
          "pi",
          ["update", "--extensions"],
          "Updating extensions...",
        );
        if (!extensions) return;

        ctx.ui.setStatus("update", "Checking updated versions...");
        const piVersionAfter = await getPiVersion();
        const packageVersionsAfter = await getInstalledPackageVersions();
        const extensionsUpdated = [...packageVersionsAfter].filter(
          ([key, version]) => packageVersionsBefore.get(key) !== version,
        ).length;

        if (!ctx.hasUI) return;

        const theme = ctx.ui.theme;
        const piSummary =
          piVersionBefore &&
          piVersionAfter &&
          piVersionBefore !== piVersionAfter
            ? `${theme.fg("success", "Pi updated:")} ${theme.fg("muted", piVersionBefore)} ${theme.fg("accent", "->")} ${theme.fg("success", piVersionAfter)}`
            : theme.fg(
                "muted",
                `Pi updated: no${piVersionAfter ? ` (${piVersionAfter})` : ""}`,
              );
        const nodeSummary = nodeUpdated
          ? `${theme.fg("success", "Node updated:")} ${theme.fg("muted", nodeVersionBefore ?? "unknown")} ${theme.fg("accent", "->")} ${theme.fg("success", nodeVersionAfter ?? "unknown")}`
          : theme.fg(
              "muted",
              `Node updated: no${nodeVersionAfter ? ` (${nodeVersionAfter})` : ""}`,
            );
        const extensionSummary =
          extensionsUpdated > 0
            ? `${theme.fg("success", "Extensions updated:")} ${theme.fg("accent", String(extensionsUpdated))}`
            : theme.fg("muted", "Extensions updated: 0");
        const summary = `${nodeSummary}\n${piSummary}\n${extensionSummary}`;

        if (nodeUpdated) {
          const exitNow = await ctx.ui.confirm(
            theme.fg("accent", theme.bold("Update complete")),
            `${summary}\n\n${theme.fg("text", "Exit Pi now to use the new Node runtime?")}`,
          );
          if (exitNow) {
            ctx.ui.setStatus("update", undefined);
            ctx.shutdown();
            return;
          }
          ctx.ui.notify(
            "Updates installed. Restart Pi to use the new Node runtime.",
            "info",
          );
          return;
        }

        const reload = await ctx.ui.confirm(
          theme.fg("accent", theme.bold("Update check complete")),
          `${summary}\n\n${theme.fg("text", "Reload extensions and resources now?")}`,
        );
        if (reload) {
          ctx.ui.setStatus("update", undefined);
          reloading = true;
          await ctx.reload();
          return;
        }

        ctx.ui.notify("Updates installed. Run /reload when ready.", "info");
      } finally {
        if (!reloading) {
          ctx.ui.setStatus("update", undefined);
        }
      }
    },
  });
}
