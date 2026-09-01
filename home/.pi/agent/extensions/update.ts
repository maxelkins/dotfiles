import {
  BorderedLoader,
  type ExecResult,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

type UpdateRunResult =
  | { kind: "completed"; result: ExecResult }
  | { kind: "cancelled" }
  | { kind: "failed"; message: string };

export default function (pi: ExtensionAPI) {
  pi.registerCommand("update", {
    description: "Update Pi and installed extensions",
    handler: async (_args, ctx) => {
      const getPiVersion = async (): Promise<string | undefined> => {
        const result = await pi.exec("pi", ["--version"]);
        return result.code === 0
          ? result.stdout.trim() || undefined
          : undefined;
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
        args: string[],
        message: string,
      ): Promise<UpdateRunResult> => {
        ctx.ui.setStatus("update", message);

        if (ctx.mode !== "tui") {
          try {
            return { kind: "completed", result: await pi.exec("pi", args) };
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
            pi.exec("pi", args, { signal: loader.signal })
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

      let reloading = false;
      try {
        ctx.ui.setStatus("update", "Checking installed versions...");
        const piVersionBefore = await getPiVersion();
        const packageVersionsBefore = await getInstalledPackageVersions();

        const self = await runUpdate(["update"], "Updating Pi...");
        if (self.kind === "cancelled") {
          ctx.ui.notify("Update cancelled.", "info");
          return;
        }
        if (self.kind === "failed" || self.result.code !== 0) {
          const message =
            self.kind === "failed"
              ? self.message
              : self.result.stderr || self.result.stdout || "Pi update failed";
          ctx.ui.notify(message, "error");
          return;
        }

        const extensions = await runUpdate(
          ["update", "--extensions"],
          "Updating extensions...",
        );
        if (extensions.kind === "cancelled") {
          ctx.ui.notify("Extension update cancelled.", "info");
          return;
        }
        if (extensions.kind === "failed" || extensions.result.code !== 0) {
          const message =
            extensions.kind === "failed"
              ? extensions.message
              : extensions.result.stderr ||
                extensions.result.stdout ||
                "Extension update failed";
          ctx.ui.notify(message, "error");
          return;
        }

        ctx.ui.setStatus("update", "Checking updated versions...");
        const piVersionAfter = await getPiVersion();
        const packageVersionsAfter = await getInstalledPackageVersions();
        const extensionsUpdated = [...packageVersionsAfter].filter(
          ([key, version]) => packageVersionsBefore.get(key) !== version,
        ).length;

        if (!ctx.hasUI) {
          return;
        }

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
        const extensionSummary =
          extensionsUpdated > 0
            ? `${theme.fg("success", "Extensions updated:")} ${theme.fg("accent", String(extensionsUpdated))}`
            : theme.fg("muted", "Extensions updated: 0");
        const summary = `${piSummary}\n${extensionSummary}`;

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
