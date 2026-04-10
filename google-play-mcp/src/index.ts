#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as dotenv from "dotenv";
import * as fs from "fs";
import { google } from "googleapis";
import * as path from "path";
import { fileURLToPath } from "url";
import { Logger } from "./logger.js";

// Load environment variables from .env file
dotenv.config({ quiet: true });

const logger = new Logger('google-play-mcp');

const PACKAGE_NAME = process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.gavra013.gavra_android';

function tryReadFile(candidatePath: string): string | null {
    if (!candidatePath) {
        return null;
    }

    const resolvedPath = path.resolve(candidatePath);
    if (!fs.existsSync(resolvedPath)) {
        return null;
    }

    try {
        const content = fs.readFileSync(resolvedPath, "utf8");
        logger.info(`Loaded service account key from file: ${resolvedPath}`);
        return content;
    } catch {
        logger.error(`Failed to read service account key from file: ${resolvedPath}`);
        return null;
    }
}

function normalizeServiceAccountKey(rawValue: string): string | null {
    const trimmedValue = rawValue.trim();
    if (!trimmedValue) {
        return null;
    }

    if (trimmedValue.startsWith('{')) {
        return trimmedValue;
    }

    const fromPath = tryReadFile(trimmedValue);
    if (fromPath) {
        return fromPath;
    }

    try {
        const decoded = Buffer.from(trimmedValue, 'base64').toString('utf8').trim();
        if (decoded.startsWith('{')) {
            logger.info('Decoded service account key from Base64');
            return decoded;
        }
    } catch {
        logger.error('Failed to decode SERVICE_ACCOUNT_KEY from Base64');
    }

    return trimmedValue;
}

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(moduleDirectory, '..');
const workspaceDirectory = path.resolve(projectDirectory, '..');

// Support JSON string, Base64 string, or file path in env var
let SERVICE_ACCOUNT_KEY = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_KEY;
if (SERVICE_ACCOUNT_KEY) {
    SERVICE_ACCOUNT_KEY = normalizeServiceAccountKey(SERVICE_ACCOUNT_KEY) ?? undefined;
}

// Fallback search paths for service account key file
const fallbackPaths = [
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY_PATH,
    path.join(projectDirectory, 'play-store-key.json'),
    path.join(workspaceDirectory, 'google-play-mcp', 'play-store-key.json'),
    path.join(process.cwd(), 'play-store-key.json'),
    path.join(process.cwd(), 'google-play-mcp', 'play-store-key.json'),
];

if (!SERVICE_ACCOUNT_KEY) {
    for (const p of fallbackPaths) {
        if (!p) {
            continue;
        }

        const fileContents = tryReadFile(p);
        if (fileContents) {
            SERVICE_ACCOUNT_KEY = fileContents;
            break;
        }
    }
}

// Validate required environment variables
if (!PACKAGE_NAME) {
    logger.error('Missing required environment variable: GOOGLE_PLAY_PACKAGE_NAME');
    process.exit(1);
}

if (!SERVICE_ACCOUNT_KEY) {
    logger.error('Missing required service account key. Set GOOGLE_PLAY_SERVICE_ACCOUNT_KEY (JSON or Base64) or GOOGLE_SERVICE_ACCOUNT_KEY_PATH');
    process.exit(1);
}

// Validate JSON
try {
    JSON.parse(SERVICE_ACCOUNT_KEY);
    logger.info('Google Play credentials validated successfully');
} catch (err) {
    logger.error('SERVICE_ACCOUNT_KEY is not valid JSON');
    process.exit(1);
}

interface TrackRelease {
    name?: string | null;
    versionCodes?: (string | null)[] | null;
    status?: string | null;
    userFraction?: number | null;
    releaseNotes?: { language?: string | null; text?: string | null }[] | null;
}

interface Track {
    track?: string | null;
    releases?: TrackRelease[] | null;
}

async function getAndroidPublisher() {
    const credentials = JSON.parse(SERVICE_ACCOUNT_KEY!);

    const auth = new google.auth.GoogleAuth({
        credentials,
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });

    const androidPublisher = google.androidpublisher({ version: "v3", auth });

    return androidPublisher;
}

async function getPlayDeveloperReporting() {
    const credentials = JSON.parse(SERVICE_ACCOUNT_KEY!);

    const auth = new google.auth.GoogleAuth({
        credentials,
        scopes: ["https://www.googleapis.com/auth/playdeveloperreporting"],
    });

    return google.playdeveloperreporting({ version: "v1beta1", auth });
}

// Status mapping for releases
function getStatusDescription(status: string | null | undefined): string {
    const statusMap: Record<string, string> = {
        draft: "Draft - Not yet published",
        completed: "Published - Live on Google Play",
        halted: "Halted - Rollout paused",
        inProgress: "In Progress - Rolling out",
        statusUnspecified: "Status unknown",
    };
    return status ? statusMap[status] || status : "Unknown";
}

// Track descriptions
function getTrackDescription(track: string | null | undefined): string {
    const trackMap: Record<string, string> = {
        production: "Production (Live)",
        beta: "Closed Testing (Beta)",
        alpha: "Internal Testing (Alpha)",
        internal: "Internal Testing",
    };
    return track ? trackMap[track] || track : "Unknown";
}

const server = new Server(
    {
        name: "google-play-mcp",
        version: "1.0.0",
    },
    {
        capabilities: {
            tools: {},
        },
    }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: "google_get_app_info",
                description: "Get detailed information about the app from Google Play Console, including all tracks and their release statuses",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_get_track_status",
                description: "Get the status of a specific track (production, beta, alpha, internal)",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, or internal",
                            enum: ["production", "beta", "alpha", "internal"],
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_list_releases",
                description: "List all releases across all tracks",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_get_review_status",
                description: "Check if there are any pending reviews or app updates in progress",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_delete_track_release",
                description: "Delete/clear releases from a specific track (removes all releases from that track)",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name to clear: production, beta, alpha, internal, or custom track name",
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_list_testers",
                description: "List all testers (email addresses and Google Groups) for a specific track",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, internal, or custom track name",
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_add_testers",
                description: "Add testers (email addresses) to a specific track. Does not remove existing testers.",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, internal, or custom track name",
                        },
                        emails: {
                            type: "array",
                            items: { type: "string" },
                            description: "Array of email addresses to add as testers",
                        },
                    },
                    required: ["track", "emails"],
                },
            },
            {
                name: "google_remove_testers",
                description: "Remove specific testers (email addresses) from a track",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, internal, or custom track name",
                        },
                        emails: {
                            type: "array",
                            items: { type: "string" },
                            description: "Array of email addresses to remove from testers",
                        },
                    },
                    required: ["track", "emails"],
                },
            },
            {
                name: "google_set_testers",
                description: "Set the complete list of testers for a track (replaces all existing testers). Can also set Google Groups.",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, internal, or custom track name",
                        },
                        emails: {
                            type: "array",
                            items: { type: "string" },
                            description: "Array of email addresses for individual testers",
                        },
                        googleGroups: {
                            type: "array",
                            items: { type: "string" },
                            description: "Array of Google Group email addresses (e.g., testers@googlegroups.com)",
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_list_reviews",
                description: "List all reviews for the app, including device info (phone model, CPU, RAM, screen). Only shows reviews from the last week.",
                inputSchema: {
                    type: "object",
                    properties: {
                        maxResults: {
                            type: "number",
                            description: "Maximum number of reviews to return (default: 10, max: 100)",
                        },
                        translationLanguage: {
                            type: "string",
                            description: "Language code to translate reviews to (e.g., 'en', 'sr')",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_review",
                description: "Get a single review by ID, including full device metadata",
                inputSchema: {
                    type: "object",
                    properties: {
                        reviewId: {
                            type: "string",
                            description: "The unique review ID",
                        },
                        translationLanguage: {
                            type: "string",
                            description: "Language code to translate the review to (e.g., 'en', 'sr')",
                        },
                    },
                    required: ["reviewId"],
                },
            },
            {
                name: "google_reply_to_review",
                description: "Reply to a user review. The user will receive a notification.",
                inputSchema: {
                    type: "object",
                    properties: {
                        reviewId: {
                            type: "string",
                            description: "The unique review ID to reply to",
                        },
                        replyText: {
                            type: "string",
                            description: "Your reply text (max 350 characters)",
                        },
                    },
                    required: ["reviewId", "replyText"],
                },
            },
            // === APP DETAILS & LISTINGS ===
            {
                name: "google_get_app_details",
                description: "Get app details including contact info, default language",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_update_app_details",
                description: "Update app contact details (email, website, phone)",
                inputSchema: {
                    type: "object",
                    properties: {
                        contactEmail: {
                            type: "string",
                            description: "Developer contact email",
                        },
                        contactPhone: {
                            type: "string",
                            description: "Developer contact phone",
                        },
                        contactWebsite: {
                            type: "string",
                            description: "Developer website URL",
                        },
                        defaultLanguage: {
                            type: "string",
                            description: "Default language code (e.g., 'en-US', 'sr')",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_list_store_listings",
                description: "List all store listings (app name, description) for all languages",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_get_store_listing",
                description: "Get store listing for a specific language",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US', 'sr', 'de')",
                        },
                    },
                    required: ["language"],
                },
            },
            {
                name: "google_update_store_listing",
                description: "Update store listing (title, description, etc.) for a language",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US', 'sr')",
                        },
                        title: {
                            type: "string",
                            description: "App title (max 30 chars)",
                        },
                        shortDescription: {
                            type: "string",
                            description: "Short description (max 80 chars)",
                        },
                        fullDescription: {
                            type: "string",
                            description: "Full description (max 4000 chars)",
                        },
                    },
                    required: ["language"],
                },
            },
            // === APK & BUNDLES ===
            {
                name: "google_list_apks",
                description: "List all APKs uploaded for the current edit",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_list_bundles",
                description: "List all Android App Bundles (AAB) uploaded",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_list_generated_apks",
                description: "List all APKs generated from an App Bundle for a specific version code",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionCode: {
                            type: "number",
                            description: "The version code to get generated APKs for",
                        },
                    },
                    required: ["versionCode"],
                },
            },
            // === TRACKS & RELEASES ===
            {
                name: "google_list_all_tracks",
                description: "List all available tracks (including custom tracks)",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "google_get_country_availability",
                description: "Get country availability for a specific track",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name: production, beta, alpha, internal",
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_promote_release",
                description: "Promote a release from one track to another (e.g., alpha to beta)",
                inputSchema: {
                    type: "object",
                    properties: {
                        fromTrack: {
                            type: "string",
                            description: "Source track (e.g., 'alpha')",
                        },
                        toTrack: {
                            type: "string",
                            description: "Destination track (e.g., 'beta', 'production')",
                        },
                        userFraction: {
                            type: "number",
                            description: "For staged rollout, fraction of users (0.0-1.0). Omit for full rollout.",
                        },
                    },
                    required: ["fromTrack", "toTrack"],
                },
            },
            {
                name: "google_halt_release",
                description: "Halt (pause) a staged rollout on a track",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name to halt",
                        },
                    },
                    required: ["track"],
                },
            },
            {
                name: "google_resume_release",
                description: "Resume a halted release with specified user fraction",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name to resume",
                        },
                        userFraction: {
                            type: "number",
                            description: "Fraction of users (0.0-1.0)",
                        },
                    },
                    required: ["track", "userFraction"],
                },
            },
            {
                name: "google_complete_rollout",
                description: "Complete a staged rollout to 100% of users",
                inputSchema: {
                    type: "object",
                    properties: {
                        track: {
                            type: "string",
                            description: "Track name to complete rollout",
                        },
                    },
                    required: ["track"],
                },
            },
            // === IN-APP PRODUCTS ===
            {
                name: "google_list_inapp_products",
                description: "List all in-app products (managed products and subscriptions)",
                inputSchema: {
                    type: "object",
                    properties: {
                        maxResults: {
                            type: "number",
                            description: "Maximum results (default: 100)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_inapp_product",
                description: "Get details of a specific in-app product",
                inputSchema: {
                    type: "object",
                    properties: {
                        sku: {
                            type: "string",
                            description: "The product SKU/ID",
                        },
                    },
                    required: ["sku"],
                },
            },
            // === SUBSCRIPTIONS ===
            {
                name: "google_list_subscriptions",
                description: "List all subscriptions",
                inputSchema: {
                    type: "object",
                    properties: {
                        maxResults: {
                            type: "number",
                            description: "Maximum results (default: 100)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_subscription",
                description: "Get details of a specific subscription",
                inputSchema: {
                    type: "object",
                    properties: {
                        productId: {
                            type: "string",
                            description: "The subscription product ID",
                        },
                    },
                    required: ["productId"],
                },
            },
            // === ORDERS & PURCHASES ===
            {
                name: "google_list_voided_purchases",
                description: "List all voided purchases (refunds, chargebacks)",
                inputSchema: {
                    type: "object",
                    properties: {
                        maxResults: {
                            type: "number",
                            description: "Maximum results (default: 100)",
                        },
                        startTime: {
                            type: "string",
                            description: "Start time in ISO format (e.g., '2024-01-01T00:00:00Z')",
                        },
                        endTime: {
                            type: "string",
                            description: "End time in ISO format",
                        },
                    },
                    required: [],
                },
            },
            // === IMAGES ===
            {
                name: "google_list_images",
                description: "List all images for a language and type",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US')",
                        },
                        imageType: {
                            type: "string",
                            description: "Image type",
                            enum: ["featureGraphic", "icon", "phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots", "tvBanner", "tvScreenshots", "wearScreenshots"],
                        },
                    },
                    required: ["language", "imageType"],
                },
            },
            {
                name: "google_delete_image",
                description: "Delete a specific image by ID",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US')",
                        },
                        imageType: {
                            type: "string",
                            description: "Image type",
                            enum: ["featureGraphic", "icon", "phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots", "tvBanner", "tvScreenshots", "wearScreenshots"],
                        },
                        imageId: {
                            type: "string",
                            description: "The image ID to delete",
                        },
                    },
                    required: ["language", "imageType", "imageId"],
                },
            },
            {
                name: "google_delete_all_images",
                description: "Delete all images of a specific type for a language",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US')",
                        },
                        imageType: {
                            type: "string",
                            description: "Image type to delete all of",
                            enum: ["featureGraphic", "icon", "phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots", "tvBanner", "tvScreenshots", "wearScreenshots"],
                        },
                    },
                    required: ["language", "imageType"],
                },
            },
            {
                name: "google_upload_image",
                description: "Upload an image (screenshot, icon, etc.) for a language",
                inputSchema: {
                    type: "object",
                    properties: {
                        language: {
                            type: "string",
                            description: "Language code (e.g., 'en-US')",
                        },
                        imageType: {
                            type: "string",
                            description: "Image type",
                            enum: ["featureGraphic", "icon", "phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots", "tvBanner", "tvScreenshots", "wearScreenshots"],
                        },
                        imagePath: {
                            type: "string",
                            description: "Absolute path to the image file",
                        },
                    },
                    required: ["language", "imageType", "imagePath"],
                },
            },
            // === PURCHASE VERIFICATION ===
            {
                name: "google_verify_product_purchase",
                description: "Verify a product (one-time) purchase using purchase token",
                inputSchema: {
                    type: "object",
                    properties: {
                        productId: {
                            type: "string",
                            description: "The product ID (SKU)",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The purchase token from the client",
                        },
                    },
                    required: ["productId", "purchaseToken"],
                },
            },
            {
                name: "google_verify_subscription_purchase",
                description: "Verify a subscription purchase using purchase token",
                inputSchema: {
                    type: "object",
                    properties: {
                        subscriptionId: {
                            type: "string",
                            description: "The subscription product ID",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The purchase token from the client",
                        },
                    },
                    required: ["subscriptionId", "purchaseToken"],
                },
            },
            {
                name: "google_acknowledge_purchase",
                description: "Acknowledge a product purchase (required within 3 days)",
                inputSchema: {
                    type: "object",
                    properties: {
                        productId: {
                            type: "string",
                            description: "The product ID (SKU)",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The purchase token",
                        },
                    },
                    required: ["productId", "purchaseToken"],
                },
            },
            {
                name: "google_consume_purchase",
                description: "Consume a consumable product purchase (allows repurchase)",
                inputSchema: {
                    type: "object",
                    properties: {
                        productId: {
                            type: "string",
                            description: "The product ID (SKU)",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The purchase token",
                        },
                    },
                    required: ["productId", "purchaseToken"],
                },
            },
            // === SUBSCRIPTION MANAGEMENT ===
            {
                name: "google_cancel_subscription",
                description: "Cancel a subscription immediately (use for refunds/disputes)",
                inputSchema: {
                    type: "object",
                    properties: {
                        subscriptionId: {
                            type: "string",
                            description: "The subscription product ID",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The subscription purchase token",
                        },
                    },
                    required: ["subscriptionId", "purchaseToken"],
                },
            },
            {
                name: "google_refund_subscription",
                description: "Refund and revoke a subscription",
                inputSchema: {
                    type: "object",
                    properties: {
                        subscriptionId: {
                            type: "string",
                            description: "The subscription product ID",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The subscription purchase token",
                        },
                    },
                    required: ["subscriptionId", "purchaseToken"],
                },
            },
            {
                name: "google_defer_subscription",
                description: "Defer billing for a subscription (extend free period)",
                inputSchema: {
                    type: "object",
                    properties: {
                        subscriptionId: {
                            type: "string",
                            description: "The subscription product ID",
                        },
                        purchaseToken: {
                            type: "string",
                            description: "The subscription purchase token",
                        },
                        expectedExpiryTime: {
                            type: "string",
                            description: "Current expected expiry time (ISO format)",
                        },
                        desiredExpiryTime: {
                            type: "string",
                            description: "New desired expiry time (ISO format)",
                        },
                    },
                    required: ["subscriptionId", "purchaseToken", "expectedExpiryTime", "desiredExpiryTime"],
                },
            },
            // === EXPANSION FILES (OBB) ===
            {
                name: "google_list_expansion_files",
                description: "List expansion files (OBB) for a specific APK version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionCode: {
                            type: "number",
                            description: "The APK version code",
                        },
                    },
                    required: ["versionCode"],
                },
            },
            // === DEOBFUSCATION FILES ===
            {
                name: "google_list_deobfuscation_files",
                description: "List deobfuscation (ProGuard/R8 mapping) files for a version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionCode: {
                            type: "number",
                            description: "The APK/AAB version code",
                        },
                    },
                    required: ["versionCode"],
                },
            },
            // === INTERNAL APP SHARING ===
            {
                name: "google_get_internal_sharing_artifacts",
                description: "Get information about internal app sharing artifacts",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP RECOVERY ===
            {
                name: "google_list_app_recovery_actions",
                description: "List app recovery actions (for crash/ANR issues)",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionCode: {
                            type: "number",
                            description: "The version code to check (optional)",
                        },
                    },
                    required: [],
                },
            },
            // === USER COMMENTS ===
            {
                name: "google_list_user_comments",
                description: "List user comments/feedback from Play Console inbox",
                inputSchema: {
                    type: "object",
                    properties: {
                        maxResults: {
                            type: "number",
                            description: "Maximum results (default: 20)",
                        },
                        startIndex: {
                            type: "number",
                            description: "Start index for pagination",
                        },
                    },
                    required: [],
                },
            },
            // === DEVICE TIER CONFIG ===
            {
                name: "google_list_device_tier_configs",
                description: "List all device tier configurations",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === REPORTING API - VITALS ===
            {
                name: "google_get_crash_rate",
                description: "Get crash rate metrics from Google Play Vitals. Shows crash-free users percentage and crash counts.",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_anr_rate",
                description: "Get ANR (Application Not Responding) rate metrics from Google Play Vitals",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_slow_rendering",
                description: "Get slow rendering metrics (jank rate, frozen frames) from Google Play Vitals",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_list_anomalies",
                description: "List detected anomalies in app metrics (spikes in crashes, ANRs, etc.)",
                inputSchema: {
                    type: "object",
                    properties: {
                        pageSize: {
                            type: "number",
                            description: "Maximum number of anomalies to return (default: 20)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_error_counts",
                description: "Get error report counts grouped by error type",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_excessive_wakeups",
                description: "Get excessive wakeup rate metrics (battery drain issues)",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_get_stuck_background_wakelocks",
                description: "Get stuck background wakelock rate metrics",
                inputSchema: {
                    type: "object",
                    properties: {
                        freshness: {
                            type: "string",
                            description: "Data freshness: DAILY or HOURLY (default: DAILY)",
                            enum: ["DAILY", "HOURLY"],
                        },
                    },
                    required: [],
                },
            },
            {
                name: "google_search_error_reports",
                description: "Search for specific error reports (crashes, ANRs) with filters",
                inputSchema: {
                    type: "object",
                    properties: {
                        filter: {
                            type: "string",
                            description: "Filter string (e.g., 'versionCode=355' or 'errorType=CRASH')",
                        },
                        pageSize: {
                            type: "number",
                            description: "Maximum results (default: 20)",
                        },
                    },
                    required: [],
                },
            },
        ],
    };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
        const androidPublisher = await getAndroidPublisher();

        switch (name) {
            case "google_get_app_info": {
                // Get app details from all tracks
                const tracksResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = tracksResponse.data.id!;

                const tracks = ["production", "beta", "alpha", "internal"];
                const trackDetails: Record<string, Track | null> = {};

                for (const track of tracks) {
                    try {
                        const trackResponse = await androidPublisher.edits.tracks.get({
                            packageName: PACKAGE_NAME,
                            editId,
                            track,
                        });
                        trackDetails[track] = trackResponse.data;
                    } catch {
                        trackDetails[track] = null;
                    }
                }

                // Delete the edit (we're just reading)
                await androidPublisher.edits.delete({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                const result = {
                    packageName: PACKAGE_NAME,
                    tracks: Object.entries(trackDetails).map(([trackName, data]) => ({
                        track: trackName,
                        trackDescription: getTrackDescription(trackName),
                        releases: data?.releases?.map((release: TrackRelease) => ({
                            name: release.name,
                            versionCodes: release.versionCodes,
                            status: release.status,
                            statusDescription: getStatusDescription(release.status),
                            userFraction: release.userFraction,
                            releaseNotes: release.releaseNotes,
                        })) || [],
                    })),
                };

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify(result, null, 2),
                        },
                    ],
                };
            }

            case "google_get_track_status": {
                const track = (args as { track: string }).track;

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                const trackResponse = await androidPublisher.edits.tracks.get({
                    packageName: PACKAGE_NAME,
                    editId,
                    track,
                });

                await androidPublisher.edits.delete({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                const trackData = trackResponse.data;
                const latestRelease = trackData.releases?.[0];

                const result = {
                    track,
                    trackDescription: getTrackDescription(track),
                    latestRelease: latestRelease ? {
                        name: latestRelease.name,
                        versionCodes: latestRelease.versionCodes,
                        status: latestRelease.status,
                        statusDescription: getStatusDescription(latestRelease.status),
                        userFraction: latestRelease.userFraction,
                        releaseNotes: latestRelease.releaseNotes,
                    } : null,
                    allReleases: trackData.releases?.map((release: TrackRelease) => ({
                        name: release.name,
                        versionCodes: release.versionCodes,
                        status: release.status,
                        statusDescription: getStatusDescription(release.status),
                    })) || [],
                };

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify(result, null, 2),
                        },
                    ],
                };
            }

            case "google_list_releases": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                const tracksResponse = await androidPublisher.edits.tracks.list({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                await androidPublisher.edits.delete({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                const allReleases = tracksResponse.data.tracks?.flatMap((track: Track) =>
                    track.releases?.map((release: TrackRelease) => ({
                        track: track.track,
                        trackDescription: getTrackDescription(track.track),
                        name: release.name,
                        versionCodes: release.versionCodes,
                        status: release.status,
                        statusDescription: getStatusDescription(release.status),
                        userFraction: release.userFraction,
                    })) || []
                ) || [];

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                packageName: PACKAGE_NAME,
                                totalReleases: allReleases.length,
                                releases: allReleases,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_get_review_status": {
                // Check for any in-progress or pending releases
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                const tracksResponse = await androidPublisher.edits.tracks.list({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                await androidPublisher.edits.delete({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                const pendingReleases = tracksResponse.data.tracks?.flatMap((track: Track) =>
                    track.releases?.filter((release: TrackRelease) =>
                        release.status === "inProgress" || release.status === "draft"
                    ).map((release: TrackRelease) => ({
                        track: track.track,
                        trackDescription: getTrackDescription(track.track),
                        name: release.name,
                        versionCodes: release.versionCodes,
                        status: release.status,
                        statusDescription: getStatusDescription(release.status),
                    })) || []
                ) || [];

                const liveReleases = tracksResponse.data.tracks?.flatMap((track: Track) =>
                    track.releases?.filter((release: TrackRelease) =>
                        release.status === "completed"
                    ).map((release: TrackRelease) => ({
                        track: track.track,
                        trackDescription: getTrackDescription(track.track),
                        name: release.name,
                        versionCodes: release.versionCodes,
                    })) || []
                ) || [];

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                packageName: PACKAGE_NAME,
                                hasPendingReleases: pendingReleases.length > 0,
                                pendingReleases,
                                liveReleases,
                                summary: pendingReleases.length > 0
                                    ? `${pendingReleases.length} release(s) pending or in progress`
                                    : "No pending releases - all releases are live or completed",
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_delete_track_release": {
                const track = (args as { track: string }).track;

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                // Get current track info first
                let currentTrack;
                try {
                    const trackResponse = await androidPublisher.edits.tracks.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });
                    currentTrack = trackResponse.data;
                } catch {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: `Track '${track}' not found`,
                                }, null, 2),
                            },
                        ],
                    };
                }

                // Clear the track by setting empty releases
                await androidPublisher.edits.tracks.update({
                    packageName: PACKAGE_NAME,
                    editId,
                    track,
                    requestBody: {
                        track,
                        releases: [],
                    },
                });

                // Commit the edit
                await androidPublisher.edits.commit({
                    packageName: PACKAGE_NAME,
                    editId,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Track '${track}' cleared successfully`,
                                previousReleases: currentTrack?.releases?.map((r: TrackRelease) => ({
                                    name: r.name,
                                    versionCodes: r.versionCodes,
                                    status: r.status,
                                })) || [],
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_list_testers": {
                const track = (args as { track: string }).track;

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                try {
                    const testersResponse = await androidPublisher.edits.testers.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const testersData = testersResponse.data;

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    track,
                                    trackDescription: getTrackDescription(track),
                                    googleGroups: testersData.googleGroups || [],
                                    googleGroupsCount: (testersData.googleGroups || []).length,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });
                    throw error;
                }
            }

            case "google_add_testers": {
                const { track, emails } = args as { track: string; emails: string[] };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                try {
                    // Get current testers first
                    const currentTestersResponse = await androidPublisher.edits.testers.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const currentGroups = currentTestersResponse.data.googleGroups || [];

                    // Add new emails (avoiding duplicates)
                    const newGroups = [...new Set([...currentGroups, ...emails])];

                    // Update testers
                    await androidPublisher.edits.testers.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            googleGroups: newGroups,
                        },
                    });

                    // Commit the edit
                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    track,
                                    message: `Added ${emails.length} tester(s) to '${track}' track`,
                                    addedEmails: emails,
                                    totalTesters: newGroups.length,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_remove_testers": {
                const { track, emails } = args as { track: string; emails: string[] };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                try {
                    // Get current testers first
                    const currentTestersResponse = await androidPublisher.edits.testers.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const currentGroups = currentTestersResponse.data.googleGroups || [];
                    const emailsToRemove = new Set(emails.map(e => e.toLowerCase()));

                    // Remove specified emails
                    const newGroups = currentGroups.filter(
                        (g): g is string => g !== null && !emailsToRemove.has(g.toLowerCase())
                    );

                    // Update testers
                    await androidPublisher.edits.testers.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            googleGroups: newGroups,
                        },
                    });

                    // Commit the edit
                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const removedCount = currentGroups.length - newGroups.length;

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    track,
                                    message: `Removed ${removedCount} tester(s) from '${track}' track`,
                                    requestedRemovals: emails,
                                    actuallyRemoved: removedCount,
                                    remainingTesters: newGroups.length,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_set_testers": {
                const { track, emails = [], googleGroups = [] } = args as {
                    track: string;
                    emails?: string[];
                    googleGroups?: string[];
                };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });

                const editId = editResponse.data.id!;

                try {
                    // Get current testers for comparison
                    const currentTestersResponse = await androidPublisher.edits.testers.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const previousGroups = currentTestersResponse.data.googleGroups || [];

                    // Combine emails and Google Groups (all are set as googleGroups in the API)
                    const allTesters = [...new Set([...emails, ...googleGroups])];

                    // Update testers
                    await androidPublisher.edits.testers.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            googleGroups: allTesters,
                        },
                    });

                    // Commit the edit
                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    track,
                                    message: `Set ${allTesters.length} tester(s) for '${track}' track`,
                                    previousCount: previousGroups.length,
                                    newCount: allTesters.length,
                                    testers: allTesters,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_list_reviews": {
                const { maxResults = 10, translationLanguage } = args as {
                    maxResults?: number;
                    translationLanguage?: string;
                };

                const params: any = {
                    packageName: PACKAGE_NAME,
                    maxResults: Math.min(maxResults, 100),
                };

                if (translationLanguage) {
                    params.translationLanguage = translationLanguage;
                }

                const response = await androidPublisher.reviews.list(params);

                const reviews = (response.data.reviews || []).map((review: any) => {
                    const comment = review.comments?.[0]?.userComment;
                    const device = comment?.deviceMetadata;

                    return {
                        reviewId: review.reviewId,
                        authorName: review.authorName,
                        rating: comment?.starRating,
                        text: comment?.text,
                        lastModified: comment?.lastModified?.seconds
                            ? new Date(parseInt(comment.lastModified.seconds) * 1000).toISOString()
                            : null,
                        appVersionCode: comment?.appVersionCode,
                        appVersionName: comment?.appVersionName,
                        device: device ? {
                            productName: device.productName,
                            manufacturer: device.manufacturer,
                            deviceClass: device.deviceClass,
                            screenDensityDpi: device.screenDensityDpi,
                            screenWidthPx: device.screenWidthPx,
                            screenHeightPx: device.screenHeightPx,
                            cpuModel: device.cpuModel,
                            cpuMake: device.cpuMake,
                            ramMb: device.ramMb,
                            glEsVersion: device.glEsVersion,
                            nativePlatform: device.nativePlatform,
                        } : null,
                        developerComment: review.comments?.find((c: any) => c.developerComment)?.developerComment?.text,
                    };
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                totalReviews: reviews.length,
                                note: "Reviews API only returns reviews from the last week",
                                reviews,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_get_review": {
                const { reviewId, translationLanguage } = args as {
                    reviewId: string;
                    translationLanguage?: string;
                };

                const params: any = {
                    packageName: PACKAGE_NAME,
                    reviewId,
                };

                if (translationLanguage) {
                    params.translationLanguage = translationLanguage;
                }

                const response = await androidPublisher.reviews.get(params);
                const review = response.data;
                const comment = review.comments?.[0]?.userComment;
                const device = comment?.deviceMetadata;

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                reviewId: review.reviewId,
                                authorName: review.authorName,
                                rating: comment?.starRating,
                                text: comment?.text,
                                originalText: comment?.originalText,
                                lastModified: comment?.lastModified?.seconds
                                    ? new Date(parseInt(comment.lastModified.seconds) * 1000).toISOString()
                                    : null,
                                reviewerLanguage: comment?.reviewerLanguage,
                                appVersionCode: comment?.appVersionCode,
                                appVersionName: comment?.appVersionName,
                                thumbsUpCount: comment?.thumbsUpCount,
                                thumbsDownCount: comment?.thumbsDownCount,
                                device: device ? {
                                    productName: device.productName,
                                    manufacturer: device.manufacturer,
                                    deviceClass: device.deviceClass,
                                    screenDensityDpi: device.screenDensityDpi,
                                    screenWidthPx: device.screenWidthPx,
                                    screenHeightPx: device.screenHeightPx,
                                    cpuModel: device.cpuModel,
                                    cpuMake: device.cpuMake,
                                    ramMb: device.ramMb,
                                    glEsVersion: device.glEsVersion,
                                    nativePlatform: device.nativePlatform,
                                } : null,
                                developerComment: review.comments?.find((c: any) => c.developerComment)?.developerComment,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_reply_to_review": {
                const { reviewId, replyText } = args as {
                    reviewId: string;
                    replyText: string;
                };

                if (replyText.length > 350) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: `Reply text is ${replyText.length} characters. Maximum allowed is 350.`,
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }

                const response = await androidPublisher.reviews.reply({
                    packageName: PACKAGE_NAME,
                    reviewId,
                    requestBody: {
                        replyText,
                    },
                });

                const result = response.data.result;

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                reviewId,
                                replyText: result?.replyText,
                                lastEdited: result?.lastEdited?.seconds
                                    ? new Date(parseInt(result.lastEdited.seconds) * 1000).toISOString()
                                    : null,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === APP DETAILS & LISTINGS IMPLEMENTATIONS ===

            case "google_get_app_details": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const detailsResponse = await androidPublisher.edits.details.get({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    details: detailsResponse.data,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_update_app_details": {
                const { contactEmail, contactPhone, contactWebsite, defaultLanguage } = args as {
                    contactEmail?: string;
                    contactPhone?: string;
                    contactWebsite?: string;
                    defaultLanguage?: string;
                };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const requestBody: any = {};
                    if (contactEmail) requestBody.contactEmail = contactEmail;
                    if (contactPhone) requestBody.contactPhone = contactPhone;
                    if (contactWebsite) requestBody.contactWebsite = contactWebsite;
                    if (defaultLanguage) requestBody.defaultLanguage = defaultLanguage;

                    await androidPublisher.edits.details.patch({
                        packageName: PACKAGE_NAME,
                        editId,
                        requestBody,
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: "App details updated successfully",
                                    updated: requestBody,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_list_store_listings": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const listingsResponse = await androidPublisher.edits.listings.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const listings = (listingsResponse.data.listings || []).map((listing: any) => ({
                        language: listing.language,
                        title: listing.title,
                        shortDescription: listing.shortDescription,
                        fullDescription: listing.fullDescription?.substring(0, 200) + (listing.fullDescription?.length > 200 ? '...' : ''),
                    }));

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    totalListings: listings.length,
                                    listings,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_get_store_listing": {
                const { language } = args as { language: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const listingResponse = await androidPublisher.edits.listings.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    language,
                                    listing: listingResponse.data,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_update_store_listing": {
                const { language, title, shortDescription, fullDescription } = args as {
                    language: string;
                    title?: string;
                    shortDescription?: string;
                    fullDescription?: string;
                };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const requestBody: any = { language };
                    if (title) requestBody.title = title;
                    if (shortDescription) requestBody.shortDescription = shortDescription;
                    if (fullDescription) requestBody.fullDescription = fullDescription;

                    await androidPublisher.edits.listings.patch({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                        requestBody,
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Store listing for '${language}' updated successfully`,
                                    updated: requestBody,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            // === APK & BUNDLES IMPLEMENTATIONS ===

            case "google_list_apks": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const apksResponse = await androidPublisher.edits.apks.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const apks = (apksResponse.data.apks || []).map((apk: any) => ({
                        versionCode: apk.versionCode,
                        sha1: apk.binary?.sha1,
                        sha256: apk.binary?.sha256,
                    }));

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    totalApks: apks.length,
                                    apks,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_list_bundles": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const bundlesResponse = await androidPublisher.edits.bundles.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const bundles = (bundlesResponse.data.bundles || []).map((bundle: any) => ({
                        versionCode: bundle.versionCode,
                        sha1: bundle.sha1,
                        sha256: bundle.sha256,
                    }));

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    totalBundles: bundles.length,
                                    bundles,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_list_generated_apks": {
                const { versionCode } = args as { versionCode: number };

                const response = await androidPublisher.generatedapks.list({
                    packageName: PACKAGE_NAME,
                    versionCode,
                });

                const generatedApks = response.data.generatedApks || [];

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                versionCode,
                                totalGeneratedApks: generatedApks.length,
                                generatedApks: generatedApks.map((apk: any) => ({
                                    variantId: apk.variantId,
                                    certificateSha256Fingerprint: apk.certificateSha256Fingerprint,
                                    generatedSplitApks: apk.generatedSplitApks?.length || 0,
                                    generatedStandaloneApks: apk.generatedStandaloneApks?.length || 0,
                                    generatedUniversalApk: !!apk.generatedUniversalApk,
                                    targetingInfo: apk.targetingInfo,
                                })),
                            }, null, 2),
                        },
                    ],
                };
            }

            // === TRACKS & RELEASES IMPLEMENTATIONS ===

            case "google_list_all_tracks": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const tracksResponse = await androidPublisher.edits.tracks.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const tracks = (tracksResponse.data.tracks || []).map((track: any) => ({
                        track: track.track,
                        releases: track.releases?.map((release: any) => ({
                            name: release.name,
                            versionCodes: release.versionCodes,
                            status: release.status,
                            userFraction: release.userFraction,
                        })),
                    }));

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    totalTracks: tracks.length,
                                    tracks,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_get_country_availability": {
                const { track } = args as { track: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const availabilityResponse = await androidPublisher.edits.countryavailability.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const countries = availabilityResponse.data.countries || [];

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    track,
                                    totalCountries: countries.length,
                                    restOfWorld: availabilityResponse.data.restOfWorld,
                                    syncWithProduction: availabilityResponse.data.syncWithProduction,
                                    countries: countries.slice(0, 50).map((c: any) => c.countryCode),
                                    note: countries.length > 50 ? `Showing first 50 of ${countries.length} countries` : undefined,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_promote_release": {
                const { fromTrack, toTrack, userFraction } = args as {
                    fromTrack: string;
                    toTrack: string;
                    userFraction?: number;
                };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    // Get the source track to find version codes
                    const sourceTrackResponse = await androidPublisher.edits.tracks.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track: fromTrack,
                    });

                    const sourceRelease = sourceTrackResponse.data.releases?.find(
                        (r: any) => r.status === 'completed' || r.status === 'inProgress'
                    );

                    if (!sourceRelease || !sourceRelease.versionCodes?.length) {
                        throw new Error(`No active release found on '${fromTrack}' track`);
                    }

                    const releaseConfig: any = {
                        versionCodes: sourceRelease.versionCodes,
                        status: userFraction ? 'inProgress' : 'completed',
                        releaseNotes: sourceRelease.releaseNotes,
                    };

                    if (userFraction) {
                        releaseConfig.userFraction = userFraction;
                    }

                    await androidPublisher.edits.tracks.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track: toTrack,
                        requestBody: {
                            track: toTrack,
                            releases: [releaseConfig],
                        },
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Release promoted from '${fromTrack}' to '${toTrack}'`,
                                    versionCodes: sourceRelease.versionCodes,
                                    userFraction: userFraction || 1.0,
                                    status: userFraction ? 'inProgress (staged rollout)' : 'completed (full rollout)',
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_halt_release": {
                const { track } = args as { track: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const trackResponse = await androidPublisher.edits.tracks.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const activeRelease = trackResponse.data.releases?.find(
                        (r: any) => r.status === 'inProgress'
                    );

                    if (!activeRelease) {
                        throw new Error(`No in-progress release found on '${track}' track to halt`);
                    }

                    await androidPublisher.edits.tracks.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            track,
                            releases: [{
                                versionCodes: activeRelease.versionCodes,
                                status: 'halted',
                                userFraction: activeRelease.userFraction,
                                releaseNotes: activeRelease.releaseNotes,
                            }],
                        },
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Release halted on '${track}' track`,
                                    versionCodes: activeRelease.versionCodes,
                                    previousUserFraction: activeRelease.userFraction,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_resume_release": {
                const { track, userFraction } = args as { track: string; userFraction: number };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const trackResponse = await androidPublisher.edits.tracks.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const haltedRelease = trackResponse.data.releases?.find(
                        (r: any) => r.status === 'halted'
                    );

                    if (!haltedRelease) {
                        throw new Error(`No halted release found on '${track}' track to resume`);
                    }

                    await androidPublisher.edits.tracks.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            track,
                            releases: [{
                                versionCodes: haltedRelease.versionCodes,
                                status: 'inProgress',
                                userFraction,
                                releaseNotes: haltedRelease.releaseNotes,
                            }],
                        },
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Release resumed on '${track}' track`,
                                    versionCodes: haltedRelease.versionCodes,
                                    userFraction,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_complete_rollout": {
                const { track } = args as { track: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const trackResponse = await androidPublisher.edits.tracks.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                    });

                    const activeRelease = trackResponse.data.releases?.find(
                        (r: any) => r.status === 'inProgress' || r.status === 'halted'
                    );

                    if (!activeRelease) {
                        throw new Error(`No active or halted release found on '${track}' track to complete`);
                    }

                    await androidPublisher.edits.tracks.update({
                        packageName: PACKAGE_NAME,
                        editId,
                        track,
                        requestBody: {
                            track,
                            releases: [{
                                versionCodes: activeRelease.versionCodes,
                                status: 'completed',
                                releaseNotes: activeRelease.releaseNotes,
                            }],
                        },
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Rollout completed to 100% on '${track}' track`,
                                    versionCodes: activeRelease.versionCodes,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            // === IN-APP PRODUCTS IMPLEMENTATIONS ===

            case "google_list_inapp_products": {
                const { maxResults = 100 } = args as { maxResults?: number };

                const response = await androidPublisher.inappproducts.list({
                    packageName: PACKAGE_NAME,
                    maxResults,
                });

                const products = (response.data.inappproduct || []).map((product: any) => {
                    const listings = product.listings as Record<string, { title?: string }> | undefined;
                    const firstListing = listings ? Object.values(listings)[0] : undefined;
                    return {
                        sku: product.sku,
                        status: product.status,
                        purchaseType: product.purchaseType,
                        defaultPrice: product.defaultPrice,
                        title: listings?.['en-US']?.title || firstListing?.title,
                    };
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                totalProducts: products.length,
                                products,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_get_inapp_product": {
                const { sku } = args as { sku: string };

                const response = await androidPublisher.inappproducts.get({
                    packageName: PACKAGE_NAME,
                    sku,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                product: response.data,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === SUBSCRIPTIONS IMPLEMENTATIONS ===

            case "google_list_subscriptions": {
                const { maxResults = 100 } = args as { maxResults?: number };

                const response = await androidPublisher.monetization.subscriptions.list({
                    packageName: PACKAGE_NAME,
                    pageSize: maxResults,
                });

                const subscriptions = (response.data.subscriptions || []).map((sub: any) => ({
                    productId: sub.productId,
                    basePlans: sub.basePlans?.map((bp: any) => ({
                        basePlanId: bp.basePlanId,
                        state: bp.state,
                        regionalConfigs: bp.regionalConfigs?.length || 0,
                    })),
                    listings: Object.keys(sub.listings || {}),
                }));

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                totalSubscriptions: subscriptions.length,
                                subscriptions,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_get_subscription": {
                const { productId } = args as { productId: string };

                const response = await androidPublisher.monetization.subscriptions.get({
                    packageName: PACKAGE_NAME,
                    productId,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                subscription: response.data,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === ORDERS & PURCHASES IMPLEMENTATIONS ===

            case "google_list_voided_purchases": {
                const { maxResults = 100, startTime, endTime } = args as {
                    maxResults?: number;
                    startTime?: string;
                    endTime?: string;
                };

                const params: any = {
                    packageName: PACKAGE_NAME,
                    maxResults,
                };

                if (startTime) params.startTime = new Date(startTime).getTime().toString();
                if (endTime) params.endTime = new Date(endTime).getTime().toString();

                const response = await androidPublisher.purchases.voidedpurchases.list(params);

                const voidedPurchases = (response.data.voidedPurchases || []).map((purchase: any) => ({
                    orderId: purchase.orderId,
                    purchaseToken: purchase.purchaseToken?.substring(0, 20) + '...',
                    purchaseTimeMillis: purchase.purchaseTimeMillis,
                    voidedTimeMillis: purchase.voidedTimeMillis,
                    voidedReason: purchase.voidedReason,
                    voidedSource: purchase.voidedSource,
                    kind: purchase.kind,
                }));

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                totalVoidedPurchases: voidedPurchases.length,
                                voidedPurchases,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === IMAGES IMPLEMENTATIONS ===

            case "google_list_images": {
                const { language, imageType } = args as { language: string; imageType: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const imagesResponse = await androidPublisher.edits.images.list({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                        imageType,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const images = (imagesResponse.data.images || []).map((image: any) => ({
                        id: image.id,
                        url: image.url,
                        sha1: image.sha1,
                        sha256: image.sha256,
                    }));

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    language,
                                    imageType,
                                    totalImages: images.length,
                                    images,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_delete_image": {
                const { language, imageType, imageId } = args as { language: string; imageType: string; imageId: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    await androidPublisher.edits.images.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                        imageType,
                        imageId,
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Image ${imageId} deleted successfully`,
                                    language,
                                    imageType,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_delete_all_images": {
                const { language, imageType } = args as { language: string; imageType: string };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    await androidPublisher.edits.images.deleteall({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                        imageType,
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `All ${imageType} images deleted for ${language}`,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            case "google_upload_image": {
                const { language, imageType, imagePath } = args as { language: string; imageType: string; imagePath: string };

                if (!fs.existsSync(imagePath)) {
                    throw new Error(`Image file not found at path: ${imagePath}`);
                }

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const mimeType = imagePath.toLowerCase().endsWith(".png") ? "image/png" : "image/jpeg";
                    const response = await androidPublisher.edits.images.upload({
                        packageName: PACKAGE_NAME,
                        editId,
                        language,
                        imageType,
                        media: {
                            mimeType,
                            body: fs.createReadStream(imagePath),
                        },
                    });

                    await androidPublisher.edits.commit({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: `Image uploaded successfully for ${language} (${imageType})`,
                                    image: response.data.image,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            // === PURCHASE VERIFICATION IMPLEMENTATIONS ===

            case "google_verify_product_purchase": {
                const { productId, purchaseToken } = args as { productId: string; purchaseToken: string };

                const response = await androidPublisher.purchases.products.get({
                    packageName: PACKAGE_NAME,
                    productId,
                    token: purchaseToken,
                });

                const purchase = response.data;
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                purchase: {
                                    orderId: purchase.orderId,
                                    purchaseState: purchase.purchaseState === 0 ? 'Purchased' : purchase.purchaseState === 1 ? 'Canceled' : 'Pending',
                                    purchaseTimeMillis: purchase.purchaseTimeMillis,
                                    consumptionState: purchase.consumptionState === 0 ? 'Not consumed' : 'Consumed',
                                    acknowledgementState: purchase.acknowledgementState === 0 ? 'Not acknowledged' : 'Acknowledged',
                                    kind: purchase.kind,
                                },
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_verify_subscription_purchase": {
                const { subscriptionId, purchaseToken } = args as { subscriptionId: string; purchaseToken: string };

                const response = await androidPublisher.purchases.subscriptionsv2.get({
                    packageName: PACKAGE_NAME,
                    token: purchaseToken,
                });

                const subscription = response.data;
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                subscription: {
                                    subscriptionState: subscription.subscriptionState,
                                    latestOrderId: subscription.latestOrderId,
                                    linkedPurchaseToken: subscription.linkedPurchaseToken ? '***' : null,
                                    startTime: subscription.startTime,
                                    expiryTime: subscription.lineItems?.[0]?.expiryTime,
                                    autoRenewing: subscription.lineItems?.[0]?.autoRenewingPlan?.autoRenewEnabled,
                                    productId: subscription.lineItems?.[0]?.productId,
                                    acknowledgementState: subscription.acknowledgementState,
                                },
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_acknowledge_purchase": {
                const { productId, purchaseToken } = args as { productId: string; purchaseToken: string };

                await androidPublisher.purchases.products.acknowledge({
                    packageName: PACKAGE_NAME,
                    productId,
                    token: purchaseToken,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Purchase acknowledged for ${productId}`,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_consume_purchase": {
                const { productId, purchaseToken } = args as { productId: string; purchaseToken: string };

                await androidPublisher.purchases.products.consume({
                    packageName: PACKAGE_NAME,
                    productId,
                    token: purchaseToken,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Purchase consumed for ${productId} - user can now repurchase`,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === SUBSCRIPTION MANAGEMENT IMPLEMENTATIONS ===

            case "google_cancel_subscription": {
                const { subscriptionId, purchaseToken } = args as { subscriptionId: string; purchaseToken: string };

                await androidPublisher.purchases.subscriptions.cancel({
                    packageName: PACKAGE_NAME,
                    subscriptionId,
                    token: purchaseToken,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Subscription ${subscriptionId} cancelled`,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_refund_subscription": {
                const { subscriptionId, purchaseToken } = args as { subscriptionId: string; purchaseToken: string };

                await androidPublisher.purchases.subscriptions.refund({
                    packageName: PACKAGE_NAME,
                    subscriptionId,
                    token: purchaseToken,
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Subscription ${subscriptionId} refunded and revoked`,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "google_defer_subscription": {
                const { subscriptionId, purchaseToken, expectedExpiryTime, desiredExpiryTime } = args as {
                    subscriptionId: string;
                    purchaseToken: string;
                    expectedExpiryTime: string;
                    desiredExpiryTime: string;
                };

                const response = await androidPublisher.purchases.subscriptions.defer({
                    packageName: PACKAGE_NAME,
                    subscriptionId,
                    token: purchaseToken,
                    requestBody: {
                        deferralInfo: {
                            expectedExpiryTimeMillis: new Date(expectedExpiryTime).getTime().toString(),
                            desiredExpiryTimeMillis: new Date(desiredExpiryTime).getTime().toString(),
                        },
                    },
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Subscription billing deferred`,
                                newExpiryTime: response.data.newExpiryTimeMillis,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === EXPANSION FILES (OBB) ===

            case "google_list_expansion_files": {
                const { versionCode } = args as { versionCode: number };

                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    const mainObb = await androidPublisher.edits.expansionfiles.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        apkVersionCode: versionCode,
                        expansionFileType: 'main',
                    }).catch(() => null);

                    const patchObb = await androidPublisher.edits.expansionfiles.get({
                        packageName: PACKAGE_NAME,
                        editId,
                        apkVersionCode: versionCode,
                        expansionFileType: 'patch',
                    }).catch(() => null);

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    versionCode,
                                    mainObb: mainObb?.data || null,
                                    patchObb: patchObb?.data || null,
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            // === DEOBFUSCATION FILES ===

            case "google_list_deobfuscation_files": {
                const { versionCode } = args as { versionCode: number };

                // Note: Deobfuscation files are uploaded with bundles/apks but not listable via API
                // Return info about what files would be associated
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                versionCode,
                                message: "Deobfuscation files (ProGuard/R8 mappings) are uploaded alongside APKs/AABs",
                                note: "Check Google Play Console > App Bundle Explorer for mapping file status",
                                supportedTypes: ["proguard", "nativeCode"],
                            }, null, 2),
                        },
                    ],
                };
            }

            // === INTERNAL APP SHARING ===

            case "google_get_internal_sharing_artifacts": {
                const editResponse = await androidPublisher.edits.insert({
                    packageName: PACKAGE_NAME,
                });
                const editId = editResponse.data.id!;

                try {
                    // Get all APKs and bundles to show what could be shared internally
                    const apksResponse = await androidPublisher.edits.apks.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    const bundlesResponse = await androidPublisher.edits.bundles.list({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: "Internal app sharing artifacts",
                                    apks: apksResponse.data.apks?.map((a: any) => ({
                                        versionCode: a.versionCode,
                                        sha256: a.binary?.sha256,
                                    })) || [],
                                    bundles: bundlesResponse.data.bundles?.map((b: any) => ({
                                        versionCode: b.versionCode,
                                        sha256: b.sha256,
                                    })) || [],
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    await androidPublisher.edits.delete({
                        packageName: PACKAGE_NAME,
                        editId,
                    }).catch(() => { });
                    throw error;
                }
            }

            // === APP RECOVERY ===

            case "google_list_app_recovery_actions": {
                const { versionCode } = args as { versionCode?: number };

                try {
                    const response = await androidPublisher.apprecovery.list({
                        packageName: PACKAGE_NAME,
                        versionCode: versionCode?.toString(),
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    recoveryActions: response.data.recoveryActions || [],
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: "No app recovery actions found or API not available",
                                    recoveryActions: [],
                                }, null, 2),
                            },
                        ],
                    };
                }
            }

            // === USER COMMENTS ===

            case "google_list_user_comments": {
                const { maxResults = 20, startIndex = 0 } = args as { maxResults?: number; startIndex?: number };

                const response = await androidPublisher.reviews.list({
                    packageName: PACKAGE_NAME,
                    maxResults,
                    startIndex,
                });

                const reviews = (response.data.reviews || []).map((review: any) => {
                    const userComment = review.comments?.[0]?.userComment;
                    return {
                        reviewId: review.reviewId,
                        authorName: review.authorName,
                        starRating: userComment?.starRating,
                        text: userComment?.text,
                        lastModified: userComment?.lastModified?.seconds,
                        device: userComment?.device,
                        androidOsVersion: userComment?.androidOsVersion,
                        appVersionCode: userComment?.appVersionCode,
                        appVersionName: userComment?.appVersionName,
                    };
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                totalReviews: reviews.length,
                                reviews,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === DEVICE TIER CONFIG ===

            case "google_list_device_tier_configs": {
                try {
                    const response = await androidPublisher.applications.deviceTierConfigs.list({
                        packageName: PACKAGE_NAME,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    deviceTierConfigs: response.data.deviceTierConfigs || [],
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    message: "No device tier configs found",
                                    deviceTierConfigs: [],
                                }, null, 2),
                            },
                        ],
                    };
                }
            }

            // === REPORTING API - VITALS ===

            case "google_get_crash_rate": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.crashrate.get({
                        name: `apps/${PACKAGE_NAME}/crashRateMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    crashRateMetrics: response.data,
                                    note: "Crash-free users rate and crash counts",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                    enableUrl: "https://console.cloud.google.com/apis/library/playdeveloperreporting.googleapis.com",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_get_anr_rate": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.anrrate.get({
                        name: `apps/${PACKAGE_NAME}/anrRateMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    anrRateMetrics: response.data,
                                    note: "ANR-free users rate and ANR counts",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_get_slow_rendering": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.slowrenderingrate.get({
                        name: `apps/${PACKAGE_NAME}/slowRenderingRateMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    slowRenderingMetrics: response.data,
                                    note: "Jank rate and frozen frames percentages",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_list_anomalies": {
                const { pageSize = 20 } = args as { pageSize?: number };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.anomalies.list({
                        parent: `apps/${PACKAGE_NAME}`,
                        pageSize,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    anomalies: response.data.anomalies || [],
                                    note: "Detected metric anomalies (spikes in crashes, ANRs, etc.)",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_get_error_counts": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.errors.counts.get({
                        name: `apps/${PACKAGE_NAME}/errorCountMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    errorCountMetrics: response.data,
                                    note: "Error counts grouped by type",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_get_excessive_wakeups": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.excessivewakeuprate.get({
                        name: `apps/${PACKAGE_NAME}/excessiveWakeupRateMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    excessiveWakeupMetrics: response.data,
                                    note: "Excessive wakeup rate (battery drain issues)",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_get_stuck_background_wakelocks": {
                const { freshness = "DAILY" } = args as { freshness?: string };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    const response = await reporting.vitals.stuckbackgroundwakelockrate.get({
                        name: `apps/${PACKAGE_NAME}/stuckBackgroundWakelockRateMetricSet`,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    freshness,
                                    stuckWakelockMetrics: response.data,
                                    note: "Stuck background wakelock rate",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            case "google_search_error_reports": {
                const { filter, pageSize = 20 } = args as { filter?: string; pageSize?: number };

                try {
                    const reporting = await getPlayDeveloperReporting();
                    // Use type assertion to handle API typing issues
                    const searchFn = reporting.vitals.errors.reports.search as any;
                    const response = await searchFn({
                        parent: `apps/${PACKAGE_NAME}`,
                        filter: filter || undefined,
                        pageSize,
                    });

                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: true,
                                    packageName: PACKAGE_NAME,
                                    errorReports: response?.data?.errorReports || [],
                                    nextPageToken: response?.data?.nextPageToken,
                                    note: "Filtered error reports",
                                }, null, 2),
                            },
                        ],
                    };
                } catch (error: any) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify({
                                    success: false,
                                    error: error.message || String(error),
                                    hint: "Ensure 'Google Play Developer Reporting API' is enabled in Google Cloud Console",
                                }, null, 2),
                            },
                        ],
                        isError: true,
                    };
                }
            }

            default:
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: false,
                                error: `Unknown tool: ${name}`,
                            }, null, 2),
                        },
                    ],
                    isError: true,
                };
        }
    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        const errorContext = {
            tool: name,
            packageName: PACKAGE_NAME,
            timestamp: new Date().toISOString(),
        };

        logger.exception(`Tool execution failed: ${name}`, error as Error, errorContext);

        return {
            content: [
                {
                    type: "text",
                    text: JSON.stringify({
                        success: false,
                        error: errorMessage,
                        tool: name,
                        packageName: PACKAGE_NAME,
                        hint: getGooglePlayErrorHint(errorMessage),
                    }, null, 2),
                },
            ],
            isError: true,
        };
    }
});

/**
 * Get helpful hints based on common Google Play API error messages
 */
function getGooglePlayErrorHint(errorMessage: string): string | undefined {
    if (errorMessage.includes('401') || errorMessage.includes('Unauthorized')) {
        return 'Check your GOOGLE_PLAY_SERVICE_ACCOUNT_KEY environment variable';
    }
    if (errorMessage.includes('403') || errorMessage.includes('Forbidden')) {
        return 'Service account may not have Android Publisher API access. Check Google Cloud Console permissions';
    }
    if (errorMessage.includes('404') || errorMessage.includes('applicationNotFound')) {
        return 'Package name not found. Verify GOOGLE_PLAY_PACKAGE_NAME is correct and the app exists in Google Play Console';
    }
    if (errorMessage.includes('Invalid JSON')) {
        return 'GOOGLE_PLAY_SERVICE_ACCOUNT_KEY contains invalid JSON. Ensure it is properly escaped';
    }
    return undefined;
}

async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    logger.info("🚀 Google Play MCP Server started");
}

main().catch((error) => {
    logger.exception('Failed to start server', error);
    process.exit(1);
});
