// Pi port of the axi-sdk-js managed opencode plugin: axi-lavish-axi.
// Source: ~/.config/opencode/plugins/axi-lavish-axi.js
//
// Runs `lavish-axi` (no args → home view) once per session and injects the
// result into the system prompt, mirroring the opencode plugin's
// "experimental.chat.system.transform" hook. Ported to Pi's
// session_start + before_agent_start events (see pi docs/extensions.md).

import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const COMMAND = "lavish-axi";
const MARKER = "lavish-axi";
const AMBIENT_HEADER = "## AXI ambient context: lavish-axi";
const TIMEOUT_MS = 10_000;

function directoryOrFallback(directory: string | undefined): string {
	return typeof directory === "string" && directory.length > 0 ? directory : process.cwd();
}

function runAxiHomeView(cwd: string): Promise<string> {
	return new Promise((resolve) => {
		const child = spawn(COMMAND, [], {
			cwd: directoryOrFallback(cwd),
			env: process.env,
			shell: false,
			stdio: ["ignore", "pipe", "pipe"],
		});

		let stdout = "";
		let stderr = "";
		let settled = false;

		const timer = setTimeout(() => {
			if (settled) return;
			settled = true;
			child.kill("SIGTERM");
			resolve(`error: ${MARKER} ambient context timed out after ${TIMEOUT_MS}ms`);
		}, TIMEOUT_MS);

		child.stdout?.setEncoding("utf-8");
		child.stderr?.setEncoding("utf-8");
		child.stdout?.on("data", (chunk) => {
			stdout += chunk;
		});
		child.stderr?.on("data", (chunk) => {
			stderr += chunk;
		});
		child.on("error", (error) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			resolve(`error: ${MARKER} ambient context failed: ${error.message}`);
		});
		child.on("close", (code) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			if (code === 0) {
				resolve(stdout.trim());
				return;
			}
			const message = (stderr || stdout || `${MARKER} exited with code ${code}`).trim();
			resolve(`error: ${MARKER} ambient context failed: ${message}`);
		});
	});
}

export default function lavishAxiAmbientContext(pi: ExtensionAPI) {
	// Cached home view; undefined = not yet fetched for this session.
	let homeView: string | undefined;

	pi.on("session_start", async (_event, ctx) => {
		homeView = undefined;
		ctx.events?.emit?.("lavish-axi:refresh", undefined);
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (homeView === undefined) {
			homeView = await runAxiHomeView(ctx.cwd);
		}
		if (homeView.length === 0) return;
		return {
			systemPrompt: `${event.systemPrompt}\n\n${AMBIENT_HEADER}\n${homeView}`,
		};
	});
}
