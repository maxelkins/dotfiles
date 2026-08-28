import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

function padCentered(text: string, width: number): string {
  const remaining = Math.max(0, width - visibleWidth(text));
  const left = Math.floor(remaining / 2);
  return `${" ".repeat(left)}${text}${" ".repeat(remaining - left)}`;
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    const home = homedir();
    const cwd = ctx.cwd === home ? "~" : ctx.cwd.startsWith(`${home}/`) ? `~${ctx.cwd.slice(home.length)}` : ctx.cwd;
    const model = ctx.model?.id ?? "no model";
    const thinking = ctx.thinkingLevel;

    ctx.ui.setHeader((_tui, theme) => ({
      render(width: number): string[] {
        if (width < 20) {
          return [truncateToWidth(`${theme.fg("accent", theme.bold("π"))} ${theme.fg("muted", "pi")}`, width, "")];
        }

        const cardWidth = Math.min(64, width - 2);
        const contentWidth = cardWidth - 2;
        const indent = " ".repeat(Math.floor((width - cardWidth) / 2));
        const border = (text: string) => theme.fg("borderMuted", text);
        const title = `${theme.fg("accent", theme.bold("π"))}  ${theme.fg("text", theme.bold("pi"))}`;
        const metadata = truncateToWidth(`${cwd}  ·  ${model}  ·  ${thinking}`, contentWidth, "…");

        return [
          "",
          `${indent}${border(`╭${"─".repeat(contentWidth)}╮`)}`,
          `${indent}${border("│")}${padCentered(title, contentWidth)}${border("│")}`,
          `${indent}${border("│")}${theme.fg("muted", padCentered(metadata, contentWidth))}${border("│")}`,
          `${indent}${border(`╰${"─".repeat(contentWidth)}╯`)}`,
          "",
        ];
      },
      invalidate() {},
    }));
  });
}
