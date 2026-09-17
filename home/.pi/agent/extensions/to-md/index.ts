import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { type AssistantMessage, uuidv7 } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

function textContent(content: unknown): string {
  if (!Array.isArray(content)) return "";

  return content
    .filter(
      (block): block is { type: "text"; text: string } =>
        typeof block === "object" &&
        block !== null &&
        "type" in block &&
        block.type === "text" &&
        "text" in block &&
        typeof block.text === "string",
    )
    .map((block) => block.text)
    .join("\n\n");
}

async function generatedFileName(
  markdown: string,
  ctx: ExtensionCommandContext,
  now = new Date(),
): Promise<string> {
  if (!ctx.model) throw new Error("No model selected");
  if (!ctx.modelRegistry.hasConfiguredAuth(ctx.model)) {
    throw new Error(`No authentication configured for ${ctx.model.id}`);
  }

  const response = await ctx.modelRegistry.complete(
    ctx.model,
    {
      systemPrompt:
        "Create a short, descriptive filename title for the Markdown provided. Return only two to six plain words. Do not include a date, extension, punctuation, quotes, or explanation.",
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: markdown.slice(0, 6000) }],
          timestamp: Date.now(),
        },
      ],
    },
    {
      reasoningEffort: "low",
      cacheRetention: "none",
      sessionId: uuidv7(),
    },
  );
  const title = textContent(response.content).trim();
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .split("-")
    .slice(0, 6)
    .join("-");
  if (!slug) throw new Error("The model did not return a usable title");

  const date = [
    String(now.getDate()).padStart(2, "0"),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getFullYear()).slice(-2),
  ].join("-");

  return `${slug}-${date}.md`;
}

export default function toMarkdownExtension(pi: ExtensionAPI) {
  pi.registerCommand("to-md", {
    description:
      "Save the latest assistant response as Markdown (optional: /to-md name)",
    handler: async (args, ctx) => {
      await ctx.waitForIdle();

      const branch = ctx.sessionManager.getBranch();
      let assistantMessage: AssistantMessage | undefined;
      for (let index = branch.length - 1; index >= 0; index--) {
        const entry = branch[index];
        if (entry?.type === "message" && entry.message.role === "assistant") {
          assistantMessage = entry.message;
          break;
        }
      }

      if (!assistantMessage) {
        ctx.ui.notify("No assistant response to save", "warning");
        return;
      }

      const markdown = textContent(assistantMessage.content);
      if (!markdown.trim()) {
        ctx.ui.notify(
          "The latest assistant response has no Markdown text",
          "warning",
        );
        return;
      }

      const name = args.trim();
      let fileName: string;
      if (name) {
        fileName = name.endsWith(".md") ? name : `${name}.md`;
      } else {
        ctx.ui.setStatus("to-md", "Generating filename...");
        try {
          fileName = await generatedFileName(markdown, ctx);
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          ctx.ui.notify(`Could not generate filename: ${message}`, "error");
          return;
        } finally {
          ctx.ui.setStatus("to-md", undefined);
        }
      }
      const path = resolve(ctx.cwd, fileName);

      try {
        await writeFile(
          path,
          markdown.endsWith("\n") ? markdown : `${markdown}\n`,
          { encoding: "utf8", flag: "wx" },
        );
      } catch (error) {
        if (
          typeof error === "object" &&
          error !== null &&
          "code" in error &&
          error.code === "EEXIST"
        ) {
          ctx.ui.notify(`File already exists: ${path}`, "error");
          return;
        }
        throw error;
      }

      const message = `Saved Markdown to ${path}`;
      pi.sendMessage(
        {
          customType: "to-md",
          content: message,
          display: true,
        },
        { deliverAs: "nextTurn" },
      );
      ctx.ui.notify(message, "info");
    },
  });
}
