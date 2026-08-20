#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import * as dotenv from "dotenv";
import * as fs from "fs";
import fetch from "node-fetch";
import * as path from "path";
dotenv.config({ path: path.resolve(process.cwd(), ".env") });
dotenv.config({ path: path.resolve(process.cwd(), "../.env") });
const workspaceRoot = process.cwd();
const possibleHuaweiDirs = [
    path.resolve(workspaceRoot, "huawei"),
    path.resolve(workspaceRoot, "../huawei"),
    path.resolve(workspaceRoot, "../production final/huawei"),
    path.resolve(workspaceRoot, "../../production final/huawei"),
    path.resolve(workspaceRoot, "C:/Users/Bojan/Desktop/production final/huawei"),
    path.resolve(workspaceRoot, "C:/Users/Bojan/Desktop/production final"),
];
function findExistingFile(fileNames, searchRoots) {
    for (const root of searchRoots) {
        if (!root || !fs.existsSync(root))
            continue;
        for (const fileName of fileNames) {
            const candidate = path.join(root, fileName);
            if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
                return candidate;
            }
        }
    }
    return null;
}
const HUAWEI_DIR = possibleHuaweiDirs.find((p) => fs.existsSync(p) && fs.statSync(p).isDirectory()) || null;
const AGCONNECT_PATH = process.env.HUAWEI_AGCONNECT_PATH ||
    findExistingFile(["agconnect-services.json"], HUAWEI_DIR ? [HUAWEI_DIR] : possibleHuaweiDirs) ||
    findExistingFile(["agconnect-services.json"], [path.resolve(workspaceRoot, ".."), path.resolve(workspaceRoot, "../..")]);
const HUAWEI_TXT_PATH = process.env.HUAWEI_TXT_PATH ||
    findExistingFile(["HUAWEI.txt"], HUAWEI_DIR ? [HUAWEI_DIR] : possibleHuaweiDirs) ||
    findExistingFile(["HUAWEI.txt"], [path.resolve(workspaceRoot, ".."), path.resolve(workspaceRoot, "../..")]);
const HUAWEI_CLIENT_ID = process.env.HUAWEI_CLIENT_ID || process.env.HUAWEI_APP_CLIENT_ID || "";
const HUAWEI_CLIENT_SECRET = process.env.HUAWEI_CLIENT_SECRET || "";
const HUAWEI_APP_ID = process.env.HUAWEI_APP_ID || "";
const HUAWEI_PACKAGE_NAME = process.env.HUAWEI_PACKAGE_NAME || "";
const HUAWEI_PROJECT_ID = process.env.HUAWEI_PROJECT_ID || "";
function safeReadFile(filePath) {
    if (!filePath)
        return null;
    try {
        return fs.readFileSync(filePath, "utf8");
    }
    catch {
        return null;
    }
}
function parseAgconnect() {
    const raw = safeReadFile(AGCONNECT_PATH);
    if (!raw)
        return null;
    try {
        return JSON.parse(raw);
    }
    catch {
        return null;
    }
}
function parseHuaweiTxt() {
    const raw = safeReadFile(HUAWEI_TXT_PATH);
    if (!raw)
        return {};
    const result = {};
    const lines = raw.split(/\r?\n/);
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#") || trimmed.startsWith("="))
            continue;
        const idx = trimmed.indexOf(":");
        if (idx > 0) {
            const key = trimmed.slice(0, idx).trim();
            const value = trimmed.slice(idx + 1).trim();
            if (key)
                result[key] = value;
        }
    }
    return result;
}
function summarizeAgconnect(data) {
    if (!data) {
        return {
            found: false,
            package_name: null,
            app_id: null,
            project_id: null,
            client_id: null,
            client_secret_present: false,
            api_key_present: false,
        };
    }
    const client = data.client || {};
    const appInfo = data.app_info || {};
    return {
        found: true,
        package_name: appInfo.package_name || client.package_name || HUAWEI_PACKAGE_NAME || null,
        app_id: appInfo.app_id || client.app_id || HUAWEI_APP_ID || null,
        project_id: client.project_id || HUAWEI_PROJECT_ID || null,
        client_id: client.client_id || HUAWEI_CLIENT_ID || null,
        client_secret_present: Boolean(client.client_secret || HUAWEI_CLIENT_SECRET),
        api_key_present: Boolean(client.api_key),
    };
}
async function testHuaweiOAuth() {
    if (!HUAWEI_CLIENT_ID || !HUAWEI_CLIENT_SECRET) {
        return {
            ok: false,
            error: "Missing HUAWEI_CLIENT_ID or HUAWEI_CLIENT_SECRET environment variables.",
        };
    }
    const body = new URLSearchParams({
        grant_type: "client_credentials",
        client_id: HUAWEI_CLIENT_ID,
        client_secret: HUAWEI_CLIENT_SECRET,
    });
    try {
        const response = await fetch("https://connect-api.cloud.huawei.com/api/oauth2/v1/token", {
            method: "POST",
            headers: {
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body: body.toString(),
        });
        const text = await response.text();
        let json = null;
        try {
            json = JSON.parse(text);
        }
        catch {
            json = { raw: text };
        }
        if (!response.ok) {
            return {
                ok: false,
                status: response.status,
                error: json?.error_description || json?.error || "Huawei OAuth failed.",
                response: json,
            };
        }
        return {
            ok: true,
            status: response.status,
            access_token_present: Boolean(json?.access_token),
            token_type: json?.token_type || null,
            expires_in: json?.expires_in || null,
            response: json,
        };
    }
    catch (error) {
        return {
            ok: false,
            error: error?.message || "Unexpected error while calling Huawei OAuth endpoint.",
        };
    }
}
const server = new Server({
    name: "huawei-mcp",
    version: "1.0.0",
}, {
    capabilities: {
        tools: {},
    },
});
server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
        {
            name: "huawei_get_config_summary",
            description: "Read Huawei AppGallery config and summarize app metadata from agconnect-services.json or environment variables.",
            inputSchema: {
                type: "object",
                properties: {},
                required: [],
            },
        },
        {
            name: "huawei_validate_config",
            description: "Validate Huawei AppGallery config file and report missing fields.",
            inputSchema: {
                type: "object",
                properties: {},
                required: [],
            },
        },
        {
            name: "huawei_get_release_checklist",
            description: "Get a practical checklist to publish an Android app on Huawei AppGallery.",
            inputSchema: {
                type: "object",
                properties: {},
                required: [],
            },
        },
        {
            name: "huawei_test_oauth",
            description: "Attempt to authenticate with Huawei AppGallery OAuth using configured client credentials.",
            inputSchema: {
                type: "object",
                properties: {},
                required: [],
            },
        },
    ],
}));
server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    switch (name) {
        case "huawei_get_config_summary": {
            const agc = parseAgconnect();
            const txt = parseHuaweiTxt();
            const summary = summarizeAgconnect(agc);
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify({
                            config_file: AGCONNECT_PATH || null,
                            txt_file: HUAWEI_TXT_PATH || null,
                            appgallery_dir: HUAWEI_DIR || null,
                            summary,
                            txt_fields: txt,
                        }, null, 2),
                    },
                ],
            };
        }
        case "huawei_validate_config": {
            const agc = parseAgconnect();
            const missing = [];
            if (!agc) {
                missing.push("agconnect-services.json not found or invalid JSON");
            }
            else {
                const client = agc.client || {};
                if (!client.client_id && !HUAWEI_CLIENT_ID)
                    missing.push("client.client_id / HUAWEI_CLIENT_ID");
                if (!client.client_secret && !HUAWEI_CLIENT_SECRET)
                    missing.push("client.client_secret / HUAWEI_CLIENT_SECRET");
                if (!client.package_name && !HUAWEI_PACKAGE_NAME)
                    missing.push("client.package_name / HUAWEI_PACKAGE_NAME");
                if (!client.app_id && !HUAWEI_APP_ID)
                    missing.push("client.app_id / HUAWEI_APP_ID");
            }
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify({
                            valid: missing.length === 0,
                            missing,
                            agconnect_path: AGCONNECT_PATH || null,
                            note: "This validation checks config completeness. It does not guarantee Huawei API acceptance without a valid AppGallery project.",
                        }, null, 2),
                    },
                ],
            };
        }
        case "huawei_get_release_checklist": {
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify({
                            platform: "Huawei AppGallery",
                            checklist: [
                                "Create or open Huawei AppGallery Connect project for the app.",
                                "Configure package name to match Android applicationId.",
                                "Upload agconnect-services.json to the app configuration or store it in the project.",
                                "Add HMS / AppGallery plugin to Android Gradle build.",
                                "Use Huawei-compatible push or fallback logic when Google Play Services are absent.",
                                "Generate a signed Android release build.",
                                "Upload APK/AAB to AppGallery Connect and complete app information.",
                                "Run release tests on a Huawei device with GMS disabled.",
                                "Submit the app for review and monitor AppGallery status.",
                            ],
                            notes: [
                                "If the app already uses Firebase Messaging, use a dual strategy: FCM on Google devices and HMS on Huawei devices.",
                                "The Huawei file is valid only if the AppGallery project and package name match your Android app exactly.",
                            ],
                        }, null, 2),
                    },
                ],
            };
        }
        case "huawei_test_oauth": {
            const result = await testHuaweiOAuth();
            return {
                content: [
                    {
                        type: "text",
                        text: JSON.stringify(result, null, 2),
                    },
                ],
            };
        }
        default:
            return {
                content: [{ type: "text", text: `Unknown tool: ${String(name)}` }],
                isError: true,
            };
    }
});
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("✅ Huawei MCP server started");
}
main().catch((error) => {
    console.error("Huawei MCP failed to start:", error);
    process.exit(1);
});
