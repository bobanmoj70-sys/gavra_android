#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import 'dotenv/config.js';
import * as fs from "fs";
import jwt from "jsonwebtoken";
import fetch from "node-fetch";

const ISSUER_ID = process.env.APP_STORE_ISSUER_ID;
const KEY_ID = process.env.APP_STORE_KEY_ID;

// Podrška za ključ iz fajla ILI direktno iz env varijable
let PRIVATE_KEY: string | undefined;
if (process.env.APP_STORE_PRIVATE_KEY_PATH) {
    // Učitaj iz fajla
    try {
        PRIVATE_KEY = fs.readFileSync(process.env.APP_STORE_PRIVATE_KEY_PATH, "utf8");
        console.error("✅ Loaded private key from file:", process.env.APP_STORE_PRIVATE_KEY_PATH);
    } catch (err) {
        console.error("❌ Failed to read private key file:", err);
    }
} else if (process.env.APP_STORE_PRIVATE_KEY) {
    // Koristi direktno iz env
    PRIVATE_KEY = process.env.APP_STORE_PRIVATE_KEY;
    console.error("✅ Using private key from environment variable");
}

const APP_ID = process.env.APP_STORE_APP_ID || "6757114361"; // Gavra 013 iOS app ID
const BUNDLE_ID = process.env.APP_STORE_BUNDLE_ID || "com.gavra013.gavra013ios";

const BASE_URL = "https://api.appstoreconnect.apple.com/v1";

interface AppStoreResponse<T> {
    data: T;
    included?: unknown[];
    links?: { self: string };
    meta?: { paging?: { total: number } };
}

interface AppAttributes {
    name: string;
    bundleId: string;
    sku: string;
    primaryLocale: string;
    availableInNewTerritories?: boolean;
    contentRightsDeclaration?: string;
}

interface AppVersionAttributes {
    versionString: string;
    platform: string;
    appStoreState: string;
    releaseType?: string;
    createdDate?: string;
}

interface BuildAttributes {
    version: string;
    uploadedDate: string;
    expirationDate: string;
    expired: boolean;
    minOsVersion: string;
    processingState: string;
    usesNonExemptEncryption?: boolean;
}

interface BetaAppReviewSubmissionAttributes {
    betaReviewState: string;
    submittedDate?: string;
}

function generateToken(): string {
    if (!ISSUER_ID || !KEY_ID || !PRIVATE_KEY) {
        throw new Error("Missing App Store Connect credentials (ISSUER_ID, KEY_ID, or PRIVATE_KEY)");
    }

    const now = Math.floor(Date.now() / 1000);
    const payload = {
        iss: ISSUER_ID,
        iat: now,
        exp: now + 20 * 60, // 20 minutes
        aud: "appstoreconnect-v1",
    };

    return jwt.sign(payload, PRIVATE_KEY, {
        algorithm: "ES256",
        header: {
            alg: "ES256",
            kid: KEY_ID,
            typ: "JWT",
        },
    });
}

async function apiRequest<T>(endpoint: string): Promise<T> {
    const token = generateToken();
    const response = await fetch(`${BASE_URL}${endpoint}`, {
        headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
        },
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`App Store Connect API error: ${response.status} - ${errorText}`);
    }

    return response.json() as Promise<T>;
}

async function apiPatchRequest<T>(endpoint: string, body: object): Promise<T> {
    const token = generateToken();
    const response = await fetch(`${BASE_URL}${endpoint}`, {
        method: "PATCH",
        headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`App Store Connect API error: ${response.status} - ${errorText}`);
    }

    return response.json() as Promise<T>;
}

// Status descriptions for App Store
function getAppStoreStateDescription(state: string): string {
    const stateMap: Record<string, string> = {
        ACCEPTED: "Accepted - Ready for distribution",
        DEVELOPER_REJECTED: "Developer Rejected",
        DEVELOPER_REMOVED_FROM_SALE: "Removed from Sale by Developer",
        IN_REVIEW: "In Review by Apple",
        INVALID_BINARY: "Invalid Binary",
        METADATA_REJECTED: "Metadata Rejected",
        PENDING_APPLE_RELEASE: "Pending Apple Release",
        PENDING_CONTRACT: "Pending Contract",
        PENDING_DEVELOPER_RELEASE: "Pending Developer Release",
        PREPARE_FOR_SUBMISSION: "Prepare for Submission",
        PREORDER_READY_FOR_SALE: "Preorder Ready for Sale",
        PROCESSING_FOR_APP_STORE: "Processing for App Store",
        READY_FOR_REVIEW: "Ready for Review",
        READY_FOR_SALE: "Ready for Sale (LIVE)",
        REJECTED: "Rejected by Apple",
        REMOVED_FROM_SALE: "Removed from Sale",
        WAITING_FOR_EXPORT_COMPLIANCE: "Waiting for Export Compliance",
        WAITING_FOR_REVIEW: "Waiting for Review",
        REPLACED_WITH_NEW_VERSION: "Replaced with New Version",
    };
    return stateMap[state] || state;
}

function getBetaReviewStateDescription(state: string): string {
    const stateMap: Record<string, string> = {
        WAITING_FOR_REVIEW: "Waiting for Beta Review",
        IN_REVIEW: "In Beta Review",
        REJECTED: "Beta Rejected",
        APPROVED: "Beta Approved",
    };
    return stateMap[state] || state;
}

function getProcessingStateDescription(state: string): string {
    const stateMap: Record<string, string> = {
        PROCESSING: "Processing",
        FAILED: "Processing Failed",
        INVALID: "Invalid",
        VALID: "Valid - Ready for Testing",
    };
    return stateMap[state] || state;
}

const server = new Server(
    {
        name: "appstore-mcp",
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
                name: "ios_get_app_info",
                description: "Get detailed information about the app from App Store Connect",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_get_app_store_versions",
                description: "Get all App Store versions and their review status",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_get_testflight_builds",
                description: "Get TestFlight builds and their status",
                inputSchema: {
                    type: "object",
                    properties: {
                        limit: {
                            type: "number",
                            description: "Number of builds to return (default: 10)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "ios_get_review_status",
                description: "Check the current review status for App Store and TestFlight",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_list_apps",
                description: "List all apps in your App Store Connect account",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_expire_build",
                description: "Expire a TestFlight build so it's no longer available for testing",
                inputSchema: {
                    type: "object",
                    properties: {
                        buildId: {
                            type: "string",
                            description: "The build ID to expire (get from ios_get_testflight_builds)",
                        },
                    },
                    required: ["buildId"],
                },
            },
            {
                name: "ios_expire_old_builds",
                description: "Expire all TestFlight builds except the latest one",
                inputSchema: {
                    type: "object",
                    properties: {
                        keepCount: {
                            type: "number",
                            description: "Number of recent builds to keep (default: 1)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "ios_reject_submission",
                description: "Cancel/reject the current App Store submission (Developer Reject). Use this to change the build before resubmitting.",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID to reject (get from ios_get_app_store_versions)",
                        },
                    },
                    required: ["versionId"],
                },
            },
            {
                name: "ios_modify_version_string",
                description: "Change the versionString (e.g. 6.0.65 → 6.0.113) of an App Store version that is in PREPARE_FOR_SUBMISSION state.",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                        versionString: {
                            type: "string",
                            description: "New version string, e.g. '6.0.113'",
                        },
                    },
                    required: ["versionId", "versionString"],
                },
            },
            {
                name: "ios_set_build_for_version",
                description: "Set/change the build for an App Store version. The version must be in PREPARE_FOR_SUBMISSION state.",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                        buildId: {
                            type: "string",
                            description: "The build ID to attach to this version",
                        },
                    },
                    required: ["versionId", "buildId"],
                },
            },
            {
                name: "ios_submit_for_review",
                description: "Submit an App Store version for review. The version must have a build attached.",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID to submit",
                        },
                    },
                    required: ["versionId"],
                },
            },
            // === APP REVIEW INFORMATION (Demo Account, Contact Info) ===
            {
                name: "ios_get_app_review_info",
                description: "Get App Review Information (demo account, contact info, notes) for a version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                    },
                    required: ["versionId"],
                },
            },
            {
                name: "ios_set_app_review_info",
                description: "Set App Review Information (demo account credentials, contact info, notes) for Apple reviewers",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                        demoAccountName: {
                            type: "string",
                            description: "Demo account username for reviewer login",
                        },
                        demoAccountPassword: {
                            type: "string",
                            description: "Demo account password for reviewer login",
                        },
                        demoAccountRequired: {
                            type: "boolean",
                            description: "Whether sign-in is required to review the app",
                        },
                        contactFirstName: {
                            type: "string",
                            description: "Contact person first name",
                        },
                        contactLastName: {
                            type: "string",
                            description: "Contact person last name",
                        },
                        contactPhone: {
                            type: "string",
                            description: "Contact phone number (with country code, e.g., +381641162560)",
                        },
                        contactEmail: {
                            type: "string",
                            description: "Contact email address",
                        },
                        notes: {
                            type: "string",
                            description: "Additional notes/instructions for Apple reviewers (e.g., how to login)",
                        },
                    },
                    required: ["versionId"],
                },
            },
            // === BETA GROUPS & TESTERS ===
            {
                name: "ios_list_beta_groups",
                description: "List all TestFlight beta groups for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_get_beta_group",
                description: "Get details of a specific beta group including testers",
                inputSchema: {
                    type: "object",
                    properties: {
                        groupId: {
                            type: "string",
                            description: "The beta group ID",
                        },
                    },
                    required: ["groupId"],
                },
            },
            {
                name: "ios_create_beta_group",
                description: "Create a new TestFlight beta group",
                inputSchema: {
                    type: "object",
                    properties: {
                        name: {
                            type: "string",
                            description: "Name of the beta group",
                        },
                        isInternalGroup: {
                            type: "boolean",
                            description: "Whether this is an internal group (default: false)",
                        },
                        publicLinkEnabled: {
                            type: "boolean",
                            description: "Whether to enable public TestFlight link",
                        },
                        publicLinkLimit: {
                            type: "number",
                            description: "Maximum number of testers via public link",
                        },
                    },
                    required: ["name"],
                },
            },
            {
                name: "ios_add_tester_to_group",
                description: "Add a tester to a beta group by email",
                inputSchema: {
                    type: "object",
                    properties: {
                        groupId: {
                            type: "string",
                            description: "The beta group ID",
                        },
                        email: {
                            type: "string",
                            description: "Tester's email address",
                        },
                        firstName: {
                            type: "string",
                            description: "Tester's first name",
                        },
                        lastName: {
                            type: "string",
                            description: "Tester's last name",
                        },
                    },
                    required: ["groupId", "email"],
                },
            },
            {
                name: "ios_list_beta_testers",
                description: "List all beta testers for the app",
                inputSchema: {
                    type: "object",
                    properties: {
                        limit: {
                            type: "number",
                            description: "Number of testers to return (default: 50)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "ios_remove_beta_tester",
                description: "Remove a beta tester from the app",
                inputSchema: {
                    type: "object",
                    properties: {
                        testerId: {
                            type: "string",
                            description: "The beta tester ID to remove",
                        },
                    },
                    required: ["testerId"],
                },
            },
            // === APP INFO & LOCALIZATIONS ===
            {
                name: "ios_list_app_localizations",
                description: "List all app info localizations (name, subtitle, privacy policy)",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_get_version_localizations",
                description: "Get version localizations (what's new, description, keywords)",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                    },
                    required: ["versionId"],
                },
            },
            {
                name: "ios_update_version_localization",
                description: "Update version localization (what's new, description, keywords)",
                inputSchema: {
                    type: "object",
                    properties: {
                        localizationId: {
                            type: "string",
                            description: "The localization ID to update",
                        },
                        whatsNew: {
                            type: "string",
                            description: "What's new in this version",
                        },
                        description: {
                            type: "string",
                            description: "App description",
                        },
                        keywords: {
                            type: "string",
                            description: "Keywords (comma-separated)",
                        },
                        promotionalText: {
                            type: "string",
                            description: "Promotional text",
                        },
                    },
                    required: ["localizationId"],
                },
            },
            // === SCREENSHOTS & PREVIEWS ===
            {
                name: "ios_list_screenshots",
                description: "List all screenshots for a version localization",
                inputSchema: {
                    type: "object",
                    properties: {
                        localizationId: {
                            type: "string",
                            description: "The version localization ID",
                        },
                    },
                    required: ["localizationId"],
                },
            },
            {
                name: "ios_delete_screenshot",
                description: "Delete a screenshot",
                inputSchema: {
                    type: "object",
                    properties: {
                        screenshotId: {
                            type: "string",
                            description: "The screenshot ID to delete",
                        },
                    },
                    required: ["screenshotId"],
                },
            },
            // === PRICING & AVAILABILITY ===
            {
                name: "ios_get_app_pricing",
                description: "Get app pricing information",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_list_territories",
                description: "List all territories where the app is available",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === IN-APP PURCHASES ===
            {
                name: "ios_list_in_app_purchases",
                description: "List all in-app purchases for the app",
                inputSchema: {
                    type: "object",
                    properties: {
                        limit: {
                            type: "number",
                            description: "Number of results (default: 50)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "ios_get_in_app_purchase",
                description: "Get details of a specific in-app purchase",
                inputSchema: {
                    type: "object",
                    properties: {
                        iapId: {
                            type: "string",
                            description: "The in-app purchase ID",
                        },
                    },
                    required: ["iapId"],
                },
            },
            // === SUBSCRIPTIONS ===
            {
                name: "ios_list_subscriptions",
                description: "List all auto-renewable subscriptions",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === CUSTOMER REVIEWS ===
            {
                name: "ios_list_customer_reviews",
                description: "List customer reviews from the App Store",
                inputSchema: {
                    type: "object",
                    properties: {
                        limit: {
                            type: "number",
                            description: "Number of reviews to return (default: 20)",
                        },
                        sort: {
                            type: "string",
                            description: "Sort order: -createdDate (newest), createdDate (oldest), -rating (highest), rating (lowest)",
                        },
                    },
                    required: [],
                },
            },
            {
                name: "ios_reply_to_review",
                description: "Reply to a customer review",
                inputSchema: {
                    type: "object",
                    properties: {
                        reviewId: {
                            type: "string",
                            description: "The customer review ID",
                        },
                        responseBody: {
                            type: "string",
                            description: "Your reply text",
                        },
                    },
                    required: ["reviewId", "responseBody"],
                },
            },
            // === PHASED RELEASE ===
            {
                name: "ios_get_phased_release",
                description: "Get phased release status for an App Store version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                    },
                    required: ["versionId"],
                },
            },
            {
                name: "ios_pause_phased_release",
                description: "Pause the phased release rollout",
                inputSchema: {
                    type: "object",
                    properties: {
                        phasedReleaseId: {
                            type: "string",
                            description: "The phased release ID",
                        },
                    },
                    required: ["phasedReleaseId"],
                },
            },
            {
                name: "ios_resume_phased_release",
                description: "Resume a paused phased release",
                inputSchema: {
                    type: "object",
                    properties: {
                        phasedReleaseId: {
                            type: "string",
                            description: "The phased release ID",
                        },
                    },
                    required: ["phasedReleaseId"],
                },
            },
            {
                name: "ios_complete_phased_release",
                description: "Complete phased release immediately (release to all users)",
                inputSchema: {
                    type: "object",
                    properties: {
                        phasedReleaseId: {
                            type: "string",
                            description: "The phased release ID",
                        },
                    },
                    required: ["phasedReleaseId"],
                },
            },
            // === BUILD DETAILS ===
            {
                name: "ios_get_build_details",
                description: "Get detailed information about a specific build",
                inputSchema: {
                    type: "object",
                    properties: {
                        buildId: {
                            type: "string",
                            description: "The build ID",
                        },
                    },
                    required: ["buildId"],
                },
            },
            {
                name: "ios_set_build_uses_encryption",
                description: "Set whether a build uses non-exempt encryption (required for TestFlight)",
                inputSchema: {
                    type: "object",
                    properties: {
                        buildId: {
                            type: "string",
                            description: "The build ID",
                        },
                        usesNonExemptEncryption: {
                            type: "boolean",
                            description: "Whether the build uses non-exempt encryption",
                        },
                    },
                    required: ["buildId", "usesNonExemptEncryption"],
                },
            },
            // === BETA BUILD LOCALIZATIONS ===
            {
                name: "ios_update_beta_build_localization",
                description: "Update TestFlight what's new text for a build",
                inputSchema: {
                    type: "object",
                    properties: {
                        buildId: {
                            type: "string",
                            description: "The build ID",
                        },
                        locale: {
                            type: "string",
                            description: "Locale code (e.g., en-US)",
                        },
                        whatsNew: {
                            type: "string",
                            description: "What's new text for TestFlight",
                        },
                    },
                    required: ["buildId", "whatsNew"],
                },
            },
            // === PRERELEASE VERSIONS ===
            {
                name: "ios_list_prerelease_versions",
                description: "List all prerelease versions (betas) for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP STORE VERSION RELEASE REQUEST ===
            {
                name: "ios_release_version",
                description: "Release an approved version manually (when set to Manual release)",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID to release",
                        },
                    },
                    required: ["versionId"],
                },
            },
            // === AGE RATING ===
            {
                name: "ios_get_age_rating",
                description: "Get the age rating declaration for a version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                    },
                    required: ["versionId"],
                },
            },
            // === APP CATEGORIES ===
            {
                name: "ios_get_app_categories",
                description: "Get the app's primary and secondary categories",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_list_available_categories",
                description: "List all available App Store categories",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP STORE VERSION EXPERIMENTS (A/B Testing) ===
            {
                name: "ios_list_experiments",
                description: "List all App Store experiments (A/B tests) for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP EVENTS (In-App Events) ===
            {
                name: "ios_list_app_events",
                description: "List all in-app events for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === CUSTOM PRODUCT PAGES ===
            {
                name: "ios_list_custom_product_pages",
                description: "List all custom product pages for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP CLIPS ===
            {
                name: "ios_list_app_clips",
                description: "List all App Clips associated with the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === GAME CENTER ===
            {
                name: "ios_list_game_center_achievements",
                description: "List all Game Center achievements",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            {
                name: "ios_list_game_center_leaderboards",
                description: "List all Game Center leaderboards",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === REVIEW SUBMISSIONS ===
            {
                name: "ios_list_review_submissions",
                description: "List all review submissions and their status",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
            // === APP STORE VERSION SUBMISSION ===
            {
                name: "ios_get_app_store_submission",
                description: "Get the submission status for an App Store version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionId: {
                            type: "string",
                            description: "The App Store version ID",
                        },
                    },
                    required: ["versionId"],
                },
            },
            // === PROMOTIONAL OFFERS ===
            {
                name: "ios_list_promotional_offers",
                description: "List promotional offers for a subscription",
                inputSchema: {
                    type: "object",
                    properties: {
                        subscriptionId: {
                            type: "string",
                            description: "The subscription ID",
                        },
                    },
                    required: ["subscriptionId"],
                },
            },
            // === BETA APP LOCALIZATION (Test Information) ===
            {
                name: "ios_update_beta_app_localization",
                description: "Update Beta App Localization (description, feedback email, etc.) for TestFlight Test Information",
                inputSchema: {
                    type: "object",
                    properties: {
                        locale: {
                            type: "string",
                            description: "Locale code (e.g., en-US)",
                            default: "en-US",
                        },
                        description: {
                            type: "string",
                            description: "Beta app description shown to testers in TestFlight",
                        },
                        feedbackEmail: {
                            type: "string",
                            description: "Email address for tester feedback",
                        },
                        marketingUrl: {
                            type: "string",
                            description: "Marketing URL",
                        },
                        privacyPolicyUrl: {
                            type: "string",
                            description: "Privacy policy URL",
                        },
                        tvOsPrivacyPolicy: {
                            type: "string",
                            description: "tvOS privacy policy text",
                        },
                    },
                    required: [],
                },
            },
            // === BETA APP REVIEW ===
            {
                name: "ios_submit_for_beta_review",
                description: "Submit a build for TestFlight beta review",
                inputSchema: {
                    type: "object",
                    properties: {
                        buildId: {
                            type: "string",
                            description: "The build ID to submit for beta review",
                        },
                    },
                    required: ["buildId"],
                },
            },
            // === DELETE BETA GROUP ===
            {
                name: "ios_delete_beta_group",
                description: "Delete a TestFlight beta group",
                inputSchema: {
                    type: "object",
                    properties: {
                        groupId: {
                            type: "string",
                            description: "The beta group ID to delete",
                        },
                    },
                    required: ["groupId"],
                },
            },
            // === ADD BUILD TO BETA GROUP ===
            {
                name: "ios_add_build_to_beta_group",
                description: "Add a build to a TestFlight beta group",
                inputSchema: {
                    type: "object",
                    properties: {
                        groupId: {
                            type: "string",
                            description: "The beta group ID",
                        },
                        buildId: {
                            type: "string",
                            description: "The build ID to add",
                        },
                    },
                    required: ["groupId", "buildId"],
                },
            },
            // === APP PREVIEW VIDEOS ===
            {
                name: "ios_list_app_previews",
                description: "List all app preview videos for a localization",
                inputSchema: {
                    type: "object",
                    properties: {
                        localizationId: {
                            type: "string",
                            description: "The version localization ID",
                        },
                    },
                    required: ["localizationId"],
                },
            },
            // === CREATE APP STORE VERSION ===
            {
                name: "ios_create_app_store_version",
                description: "Create a new App Store version",
                inputSchema: {
                    type: "object",
                    properties: {
                        versionString: {
                            type: "string",
                            description: "Version string (e.g., '1.2.3')",
                        },
                        platform: {
                            type: "string",
                            description: "Platform: IOS, MAC_OS, TV_OS, VISION_OS",
                            enum: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"],
                        },
                        releaseType: {
                            type: "string",
                            description: "Release type: MANUAL or AFTER_APPROVAL",
                            enum: ["MANUAL", "AFTER_APPROVAL"],
                        },
                    },
                    required: ["versionString", "platform"],
                },
            },
            // === APP INFO LOCALIZATION UPDATE ===
            {
                name: "ios_update_app_info_localization",
                description: "Update app info localization (name, subtitle, privacy policy URL)",
                inputSchema: {
                    type: "object",
                    properties: {
                        localizationId: {
                            type: "string",
                            description: "The app info localization ID",
                        },
                        name: {
                            type: "string",
                            description: "App name",
                        },
                        subtitle: {
                            type: "string",
                            description: "App subtitle",
                        },
                        privacyPolicyUrl: {
                            type: "string",
                            description: "Privacy policy URL",
                        },
                        privacyChoicesUrl: {
                            type: "string",
                            description: "Privacy choices URL",
                        },
                    },
                    required: ["localizationId"],
                },
            },
            // === END USER LICENSE AGREEMENT ===
            {
                name: "ios_get_eula",
                description: "Get the End User License Agreement for the app",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: [],
                },
            },
        ],
    };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
        switch (name) {
            case "ios_get_app_info": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: AppAttributes }>>(`/apps/${APP_ID}`);

                const app = response.data;
                const result = {
                    appId: app.id,
                    name: app.attributes.name,
                    bundleId: app.attributes.bundleId,
                    sku: app.attributes.sku,
                    primaryLocale: app.attributes.primaryLocale,
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

            case "ios_get_app_store_versions": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: AppVersionAttributes }[]>>(
                    `/apps/${APP_ID}/appStoreVersions?limit=10`
                );

                const versions = response.data.map((version) => ({
                    versionId: version.id,
                    versionString: version.attributes.versionString,
                    platform: version.attributes.platform,
                    appStoreState: version.attributes.appStoreState,
                    appStoreStateDescription: getAppStoreStateDescription(version.attributes.appStoreState),
                    releaseType: version.attributes.releaseType,
                    createdDate: version.attributes.createdDate,
                }));

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                appId: APP_ID,
                                bundleId: BUNDLE_ID,
                                totalVersions: versions.length,
                                versions,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_get_testflight_builds": {
                const limit = (args as { limit?: number }).limit || 10;

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: BuildAttributes }[]>>(
                    `/builds?filter[app]=${APP_ID}&limit=${limit}&sort=-uploadedDate`
                );

                const builds = response.data.map((build) => ({
                    buildId: build.id,
                    version: build.attributes.version,
                    uploadedDate: build.attributes.uploadedDate,
                    expirationDate: build.attributes.expirationDate,
                    expired: build.attributes.expired,
                    minOsVersion: build.attributes.minOsVersion,
                    processingState: build.attributes.processingState,
                    processingStateDescription: getProcessingStateDescription(build.attributes.processingState),
                }));

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                appId: APP_ID,
                                bundleId: BUNDLE_ID,
                                totalBuilds: builds.length,
                                builds,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_get_review_status": {
                // Get App Store versions
                const versionsResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: AppVersionAttributes }[]>>(
                    `/apps/${APP_ID}/appStoreVersions?limit=5`
                );

                // Get recent builds
                const buildsResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: BuildAttributes }[]>>(
                    `/builds?filter[app]=${APP_ID}&limit=5&sort=-uploadedDate`
                );

                // Get beta review submissions
                let betaReviews: { buildId: string; betaReviewState: string; betaReviewStateDescription: string; submittedDate?: string }[] = [];
                try {
                    const betaResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: BetaAppReviewSubmissionAttributes; relationships?: { build?: { data?: { id: string } } } }[]>>(
                        `/betaAppReviewSubmissions?filter[app]=${APP_ID}&limit=5`
                    );
                    betaReviews = betaResponse.data.map((submission) => ({
                        buildId: submission.relationships?.build?.data?.id || "unknown",
                        betaReviewState: submission.attributes.betaReviewState,
                        betaReviewStateDescription: getBetaReviewStateDescription(submission.attributes.betaReviewState),
                        submittedDate: submission.attributes.submittedDate,
                    }));
                } catch {
                    // Beta reviews might not exist
                }

                const appStoreVersions = versionsResponse.data.map((v) => ({
                    versionString: v.attributes.versionString,
                    platform: v.attributes.platform,
                    state: v.attributes.appStoreState,
                    stateDescription: getAppStoreStateDescription(v.attributes.appStoreState),
                }));

                const pendingVersions = appStoreVersions.filter((v) =>
                    ["IN_REVIEW", "WAITING_FOR_REVIEW", "READY_FOR_REVIEW", "PREPARE_FOR_SUBMISSION"].includes(v.state)
                );

                const liveVersions = appStoreVersions.filter((v) => v.state === "READY_FOR_SALE");

                const latestBuild = buildsResponse.data[0];

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                appId: APP_ID,
                                bundleId: BUNDLE_ID,
                                appStoreStatus: {
                                    hasPendingReview: pendingVersions.length > 0,
                                    pendingVersions,
                                    liveVersions,
                                    allVersions: appStoreVersions,
                                },
                                testFlightStatus: {
                                    latestBuild: latestBuild ? {
                                        version: latestBuild.attributes.version,
                                        uploadedDate: latestBuild.attributes.uploadedDate,
                                        processingState: latestBuild.attributes.processingState,
                                        processingStateDescription: getProcessingStateDescription(latestBuild.attributes.processingState),
                                        expired: latestBuild.attributes.expired,
                                    } : null,
                                    betaReviews,
                                },
                                summary: pendingVersions.length > 0
                                    ? `App Store: ${pendingVersions[0].stateDescription}`
                                    : liveVersions.length > 0
                                        ? `App Store: Live (${liveVersions[0].versionString})`
                                        : "No active App Store version",
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_list_apps": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: AppAttributes }[]>>("/apps?limit=50");

                const apps = response.data.map((app) => ({
                    appId: app.id,
                    name: app.attributes.name,
                    bundleId: app.attributes.bundleId,
                    sku: app.attributes.sku,
                    primaryLocale: app.attributes.primaryLocale,
                }));

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                totalApps: apps.length,
                                apps,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_expire_build": {
                const { buildId } = args as { buildId: string };

                if (!buildId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "buildId is required" }, null, 2) }],
                        isError: true,
                    };
                }

                // PATCH /v1/builds/{id} with expired: true
                await apiPatchRequest(`/builds/${buildId}`, {
                    data: {
                        type: "builds",
                        id: buildId,
                        attributes: {
                            expired: true,
                        },
                    },
                });

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Build ${buildId} has been expired`,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_expire_old_builds": {
                const { keepCount = 1 } = args as { keepCount?: number };

                // Get all builds
                const buildsResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: BuildAttributes }[]>>(
                    `/builds?filter[app]=${APP_ID}&sort=-uploadedDate&limit=50`
                );

                const allBuilds = buildsResponse.data;
                const buildsToExpire = allBuilds
                    .filter((b) => !b.attributes.expired)
                    .slice(keepCount); // Skip the first 'keepCount' builds

                const expiredBuilds: string[] = [];
                const failedBuilds: string[] = [];

                for (const build of buildsToExpire) {
                    try {
                        await apiPatchRequest(`/builds/${build.id}`, {
                            data: {
                                type: "builds",
                                id: build.id,
                                attributes: {
                                    expired: true,
                                },
                            },
                        });
                        expiredBuilds.push(build.attributes.version);
                    } catch (e) {
                        failedBuilds.push(build.attributes.version);
                    }
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Expired ${expiredBuilds.length} builds, kept ${keepCount} latest`,
                                expiredBuilds,
                                failedBuilds: failedBuilds.length > 0 ? failedBuilds : undefined,
                                keptBuilds: allBuilds.slice(0, keepCount).map((b) => b.attributes.version),
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_reject_submission": {
                const { versionId } = args as { versionId: string };

                if (!versionId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "versionId is required" }, null, 2) }],
                        isError: true,
                    };
                }

                const token = generateToken();

                // First, find the reviewSubmission for this app that's in WAITING_FOR_REVIEW state
                const reviewSubmissionsResponse = await fetch(
                    `${BASE_URL}/reviewSubmissions?filter[app]=${APP_ID}&filter[state]=WAITING_FOR_REVIEW`,
                    {
                        headers: {
                            Authorization: `Bearer ${token}`,
                            "Content-Type": "application/json",
                        },
                    }
                );

                if (!reviewSubmissionsResponse.ok) {
                    const errorText = await reviewSubmissionsResponse.text();
                    throw new Error(`Failed to get review submissions: ${reviewSubmissionsResponse.status} - ${errorText}`);
                }

                const reviewSubmissions = await reviewSubmissionsResponse.json() as { data: { id: string; attributes: { state: string } }[] };

                if (!reviewSubmissions.data || reviewSubmissions.data.length === 0) {
                    throw new Error("No pending review submission found. The app might not be in review.");
                }

                const submissionId = reviewSubmissions.data[0].id;

                // PATCH the reviewSubmission to CANCELING state
                const cancelResponse = await fetch(`${BASE_URL}/reviewSubmissions/${submissionId}`, {
                    method: "PATCH",
                    headers: {
                        Authorization: `Bearer ${token}`,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        data: {
                            type: "reviewSubmissions",
                            id: submissionId,
                            attributes: {
                                canceled: true,
                            },
                        },
                    }),
                });

                if (!cancelResponse.ok) {
                    const errorText = await cancelResponse.text();
                    throw new Error(`Failed to cancel submission: ${cancelResponse.status} - ${errorText}`);
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Review submission ${submissionId} has been cancelled. Version is now back to PREPARE_FOR_SUBMISSION state. You can now change the build.`,
                                submissionId: submissionId,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_modify_version_string": {
                const { versionId: vsVersionId, versionString: newVersionString } = args as { versionId: string; versionString: string };
                const result = await apiPatchRequest<any>(`/appStoreVersions/${vsVersionId}`, {
                    data: {
                        type: "appStoreVersions",
                        id: vsVersionId,
                        attributes: {
                            versionString: newVersionString,
                        },
                    },
                });
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            success: true,
                            newVersionString: result.data?.attributes?.versionString,
                            versionId: result.data?.id,
                        }, null, 2),
                    }],
                };
            }

            case "ios_set_build_for_version": {
                const { versionId, buildId } = args as { versionId: string; buildId: string };

                if (!versionId || !buildId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "versionId and buildId are required" }, null, 2) }],
                        isError: true,
                    };
                }

                // PATCH /v1/appStoreVersions/{id}/relationships/build
                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appStoreVersions/${versionId}/relationships/build`, {
                    method: "PATCH",
                    headers: {
                        Authorization: `Bearer ${token}`,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        data: {
                            type: "builds",
                            id: buildId,
                        },
                    }),
                });

                if (!response.ok) {
                    const errorText = await response.text();
                    throw new Error(`Failed to set build: ${response.status} - ${errorText}`);
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Build ${buildId} has been set for version ${versionId}`,
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_submit_for_review": {
                const { versionId } = args as { versionId: string };

                if (!versionId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "versionId is required" }, null, 2) }],
                        isError: true,
                    };
                }

                // POST /v1/appStoreVersionSubmissions
                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appStoreVersionSubmissions`, {
                    method: "POST",
                    headers: {
                        Authorization: `Bearer ${token}`,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        data: {
                            type: "appStoreVersionSubmissions",
                            relationships: {
                                appStoreVersion: {
                                    data: {
                                        type: "appStoreVersions",
                                        id: versionId,
                                    },
                                },
                            },
                        },
                    }),
                });

                if (!response.ok) {
                    const errorText = await response.text();
                    throw new Error(`Failed to submit for review: ${response.status} - ${errorText}`);
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: `Version ${versionId} has been submitted for App Store review!`,
                            }, null, 2),
                        },
                    ],
                };
            }

            // === APP REVIEW INFORMATION (Demo Account, Contact Info) ===

            case "ios_get_app_review_info": {
                const { versionId } = args as { versionId: string };

                if (!versionId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "versionId is required" }, null, 2) }],
                        isError: true,
                    };
                }

                const response = await apiRequest<AppStoreResponse<{
                    id: string;
                    attributes: {
                        contactFirstName?: string;
                        contactLastName?: string;
                        contactPhone?: string;
                        contactEmail?: string;
                        demoAccountName?: string;
                        demoAccountPassword?: string;
                        demoAccountRequired?: boolean;
                        notes?: string;
                    }
                }>>(
                    `/appStoreVersions/${versionId}/appStoreReviewDetail`
                );

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                versionId,
                                reviewInfo: {
                                    id: response.data.id,
                                    contactFirstName: response.data.attributes.contactFirstName,
                                    contactLastName: response.data.attributes.contactLastName,
                                    contactPhone: response.data.attributes.contactPhone,
                                    contactEmail: response.data.attributes.contactEmail,
                                    demoAccountName: response.data.attributes.demoAccountName,
                                    demoAccountPassword: response.data.attributes.demoAccountPassword ? "********" : null,
                                    demoAccountRequired: response.data.attributes.demoAccountRequired,
                                    notes: response.data.attributes.notes,
                                },
                            }, null, 2),
                        },
                    ],
                };
            }

            case "ios_set_app_review_info": {
                const {
                    versionId,
                    demoAccountName,
                    demoAccountPassword,
                    demoAccountRequired,
                    contactFirstName,
                    contactLastName,
                    contactPhone,
                    contactEmail,
                    notes
                } = args as {
                    versionId: string;
                    demoAccountName?: string;
                    demoAccountPassword?: string;
                    demoAccountRequired?: boolean;
                    contactFirstName?: string;
                    contactLastName?: string;
                    contactPhone?: string;
                    contactEmail?: string;
                    notes?: string;
                };

                if (!versionId) {
                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: false, error: "versionId is required" }, null, 2) }],
                        isError: true,
                    };
                }

                // First get the existing review detail ID
                const existingResponse = await apiRequest<AppStoreResponse<{ id: string }>>(
                    `/appStoreVersions/${versionId}/appStoreReviewDetail`
                );

                const reviewDetailId = existingResponse.data.id;

                // Build attributes object with only provided fields
                const attributes: Record<string, any> = {};
                if (demoAccountName !== undefined) attributes.demoAccountName = demoAccountName;
                if (demoAccountPassword !== undefined) attributes.demoAccountPassword = demoAccountPassword;
                if (demoAccountRequired !== undefined) attributes.demoAccountRequired = demoAccountRequired;
                if (contactFirstName !== undefined) attributes.contactFirstName = contactFirstName;
                if (contactLastName !== undefined) attributes.contactLastName = contactLastName;
                if (contactPhone !== undefined) attributes.contactPhone = contactPhone;
                if (contactEmail !== undefined) attributes.contactEmail = contactEmail;
                if (notes !== undefined) attributes.notes = notes;

                // PATCH the review detail
                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appStoreReviewDetails/${reviewDetailId}`, {
                    method: "PATCH",
                    headers: {
                        Authorization: `Bearer ${token}`,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        data: {
                            type: "appStoreReviewDetails",
                            id: reviewDetailId,
                            attributes,
                        },
                    }),
                });

                if (!response.ok) {
                    const errorText = await response.text();
                    throw new Error(`Failed to update review info: ${response.status} - ${errorText}`);
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                success: true,
                                message: "App Review Information updated successfully!",
                                updatedFields: Object.keys(attributes),
                            }, null, 2),
                        },
                    ],
                };
            }

            // === BETA GROUPS & TESTERS ===

            case "ios_list_beta_groups": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; isInternalGroup: boolean; publicLinkEnabled: boolean; publicLinkId?: string; publicLinkLimit?: number; createdDate: string } }[]>>(
                    `/apps/${APP_ID}/betaGroups?limit=50`
                );

                const groups = response.data.map((group) => ({
                    groupId: group.id,
                    name: group.attributes.name,
                    isInternalGroup: group.attributes.isInternalGroup,
                    publicLinkEnabled: group.attributes.publicLinkEnabled,
                    publicLinkId: group.attributes.publicLinkId,
                    publicLinkLimit: group.attributes.publicLinkLimit,
                    createdDate: group.attributes.createdDate,
                }));

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalGroups: groups.length, groups }, null, 2) }],
                };
            }

            case "ios_get_beta_group": {
                const { groupId } = args as { groupId: string };

                const [groupResponse, testersResponse] = await Promise.all([
                    apiRequest<AppStoreResponse<{ id: string; attributes: any }>>(`/betaGroups/${groupId}`),
                    apiRequest<AppStoreResponse<{ id: string; attributes: { email: string; firstName?: string; lastName?: string; inviteType: string } }[]>>(`/betaGroups/${groupId}/betaTesters?limit=100`),
                ]);

                return {
                    content: [{
                        type: "text", text: JSON.stringify({
                            success: true,
                            group: { groupId: groupResponse.data.id, ...groupResponse.data.attributes },
                            testers: testersResponse.data.map(t => ({ testerId: t.id, ...t.attributes })),
                            testerCount: testersResponse.data.length,
                        }, null, 2)
                    }],
                };
            }

            case "ios_create_beta_group": {
                const { name, isInternalGroup = false, publicLinkEnabled, publicLinkLimit } = args as { name: string; isInternalGroup?: boolean; publicLinkEnabled?: boolean; publicLinkLimit?: number };

                const token = generateToken();
                const body: any = {
                    data: {
                        type: "betaGroups",
                        attributes: { name, isInternalGroup },
                        relationships: { app: { data: { type: "apps", id: APP_ID } } },
                    },
                };
                if (publicLinkEnabled !== undefined) body.data.attributes.publicLinkEnabled = publicLinkEnabled;
                if (publicLinkLimit !== undefined) body.data.attributes.publicLinkLimit = publicLinkLimit;

                const response = await fetch(`${BASE_URL}/betaGroups`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify(body),
                });

                if (!response.ok) throw new Error(`Failed to create beta group: ${response.status} - ${await response.text()}`);
                const result = await response.json() as { data: { id: string } };

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Beta group '${name}' created`, groupId: result.data.id }, null, 2) }],
                };
            }

            case "ios_add_tester_to_group": {
                const { groupId, email, firstName, lastName } = args as { groupId: string; email: string; firstName?: string; lastName?: string };

                const token = generateToken();
                // First create the beta tester
                const createResponse = await fetch(`${BASE_URL}/betaTesters`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: {
                            type: "betaTesters",
                            attributes: { email, firstName, lastName },
                            relationships: {
                                betaGroups: { data: [{ type: "betaGroups", id: groupId }] },
                            },
                        },
                    }),
                });

                if (!createResponse.ok) throw new Error(`Failed to add tester: ${createResponse.status} - ${await createResponse.text()}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Tester ${email} added to group` }, null, 2) }],
                };
            }

            case "ios_list_beta_testers": {
                const { limit = 50 } = args as { limit?: number };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { email: string; firstName?: string; lastName?: string; inviteType: string; state: string } }[]>>(
                    `/betaTesters?filter[apps]=${APP_ID}&limit=${limit}`
                );

                const testers = response.data.map(t => ({ testerId: t.id, ...t.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalTesters: testers.length, testers }, null, 2) }],
                };
            }

            case "ios_remove_beta_tester": {
                const { testerId } = args as { testerId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/betaTesters/${testerId}`, {
                    method: "DELETE",
                    headers: { Authorization: `Bearer ${token}` },
                });

                if (!response.ok) throw new Error(`Failed to remove tester: ${response.status}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Tester ${testerId} removed` }, null, 2) }],
                };
            }

            // === APP INFO & LOCALIZATIONS ===

            case "ios_list_app_localizations": {
                // First get appInfos
                const appInfosResponse = await apiRequest<AppStoreResponse<{ id: string }[]>>(`/apps/${APP_ID}/appInfos?limit=1`);
                if (!appInfosResponse.data.length) throw new Error("No app info found");

                const appInfoId = appInfosResponse.data[0].id;
                const locResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: { locale: string; name?: string; subtitle?: string; privacyPolicyUrl?: string } }[]>>(
                    `/appInfos/${appInfoId}/appInfoLocalizations?limit=50`
                );

                const localizations = locResponse.data.map(l => ({ localizationId: l.id, ...l.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, appInfoId, localizations }, null, 2) }],
                };
            }

            case "ios_get_version_localizations": {
                const { versionId } = args as { versionId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { locale: string; description?: string; keywords?: string; whatsNew?: string; promotionalText?: string } }[]>>(
                    `/appStoreVersions/${versionId}/appStoreVersionLocalizations?limit=50`
                );

                const localizations = response.data.map(l => ({ localizationId: l.id, ...l.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, versionId, localizations }, null, 2) }],
                };
            }

            case "ios_update_version_localization": {
                const { localizationId, whatsNew, description, keywords, promotionalText } = args as { localizationId: string; whatsNew?: string; description?: string; keywords?: string; promotionalText?: string };

                const attributes: any = {};
                if (whatsNew) attributes.whatsNew = whatsNew;
                if (description) attributes.description = description;
                if (keywords) attributes.keywords = keywords;
                if (promotionalText) attributes.promotionalText = promotionalText;

                await apiPatchRequest(`/appStoreVersionLocalizations/${localizationId}`, {
                    data: { type: "appStoreVersionLocalizations", id: localizationId, attributes },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Localization updated", updated: attributes }, null, 2) }],
                };
            }

            // === SCREENSHOTS ===

            case "ios_list_screenshots": {
                const { localizationId } = args as { localizationId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { fileSize: number; fileName: string; sourceFileChecksum?: string; assetDeliveryState: { state: string } } }[]>>(
                    `/appStoreVersionLocalizations/${localizationId}/appScreenshotSets?include=appScreenshots&limit=50`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, localizationId, screenshotSets: response.data }, null, 2) }],
                };
            }

            case "ios_delete_screenshot": {
                const { screenshotId } = args as { screenshotId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appScreenshots/${screenshotId}`, {
                    method: "DELETE",
                    headers: { Authorization: `Bearer ${token}` },
                });

                if (!response.ok) throw new Error(`Failed to delete screenshot: ${response.status}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Screenshot ${screenshotId} deleted` }, null, 2) }],
                };
            }

            // === PRICING & TERRITORIES ===

            case "ios_get_app_pricing": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: any }[]>>(`/apps/${APP_ID}/appPriceSchedule?include=baseTerritory,manualPrices`);
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, pricing: response }, null, 2) }],
                };
            }

            case "ios_list_territories": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { currency: string } }[]>>(`/apps/${APP_ID}/availableTerritories?limit=200`);

                const territories = response.data.map(t => ({ territoryId: t.id, currency: t.attributes.currency }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalTerritories: territories.length, territories }, null, 2) }],
                };
            }

            // === IN-APP PURCHASES ===

            case "ios_list_in_app_purchases": {
                const { limit = 50 } = args as { limit?: number };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; productId: string; inAppPurchaseType: string; state: string } }[]>>(
                    `/apps/${APP_ID}/inAppPurchasesV2?limit=${limit}`
                );

                const iaps = response.data.map(i => ({ iapId: i.id, ...i.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalIAPs: iaps.length, inAppPurchases: iaps }, null, 2) }],
                };
            }

            case "ios_get_in_app_purchase": {
                const { iapId } = args as { iapId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: any }>>(`/inAppPurchasesV2/${iapId}?include=iapPriceSchedule,inAppPurchaseLocalizations`);
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, inAppPurchase: response.data }, null, 2) }],
                };
            }

            // === SUBSCRIPTIONS ===

            case "ios_list_subscriptions": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; productId: string; groupLevel: number; state: string } }[]>>(
                    `/apps/${APP_ID}/subscriptionGroups?include=subscriptions&limit=50`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, subscriptionGroups: response.data }, null, 2) }],
                };
            }

            // === CUSTOMER REVIEWS ===

            case "ios_list_customer_reviews": {
                const { limit = 20, sort = "-createdDate" } = args as { limit?: number; sort?: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { rating: number; title?: string; body?: string; reviewerNickname: string; createdDate: string; territory: string } }[]>>(
                    `/apps/${APP_ID}/customerReviews?limit=${limit}&sort=${sort}`
                );

                const reviews = response.data.map(r => ({ reviewId: r.id, ...r.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalReviews: reviews.length, reviews }, null, 2) }],
                };
            }

            case "ios_reply_to_review": {
                const { reviewId, responseBody } = args as { reviewId: string; responseBody: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/customerReviewResponses`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: {
                            type: "customerReviewResponses",
                            attributes: { responseBody },
                            relationships: { review: { data: { type: "customerReviews", id: reviewId } } },
                        },
                    }),
                });

                if (!response.ok) throw new Error(`Failed to reply: ${response.status} - ${await response.text()}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Reply posted successfully" }, null, 2) }],
                };
            }

            // === PHASED RELEASE ===

            case "ios_get_phased_release": {
                const { versionId } = args as { versionId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { phasedReleaseState: string; startDate?: string; totalPauseDuration?: number; currentDayNumber?: number } }>>(
                    `/appStoreVersions/${versionId}/appStoreVersionPhasedRelease`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, phasedRelease: { phasedReleaseId: response.data.id, ...response.data.attributes } }, null, 2) }],
                };
            }

            case "ios_pause_phased_release": {
                const { phasedReleaseId } = args as { phasedReleaseId: string };

                await apiPatchRequest(`/appStoreVersionPhasedReleases/${phasedReleaseId}`, {
                    data: { type: "appStoreVersionPhasedReleases", id: phasedReleaseId, attributes: { phasedReleaseState: "PAUSED" } },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Phased release paused" }, null, 2) }],
                };
            }

            case "ios_resume_phased_release": {
                const { phasedReleaseId } = args as { phasedReleaseId: string };

                await apiPatchRequest(`/appStoreVersionPhasedReleases/${phasedReleaseId}`, {
                    data: { type: "appStoreVersionPhasedReleases", id: phasedReleaseId, attributes: { phasedReleaseState: "ACTIVE" } },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Phased release resumed" }, null, 2) }],
                };
            }

            case "ios_complete_phased_release": {
                const { phasedReleaseId } = args as { phasedReleaseId: string };

                await apiPatchRequest(`/appStoreVersionPhasedReleases/${phasedReleaseId}`, {
                    data: { type: "appStoreVersionPhasedReleases", id: phasedReleaseId, attributes: { phasedReleaseState: "COMPLETE" } },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Phased release completed - now available to all users" }, null, 2) }],
                };
            }

            // === BUILD DETAILS ===

            case "ios_get_build_details": {
                const { buildId } = args as { buildId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: BuildAttributes }>>(`/builds/${buildId}?include=preReleaseVersion,betaBuildLocalizations,buildBetaDetail`);
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, build: { buildId: response.data.id, ...response.data.attributes }, included: response.included }, null, 2) }],
                };
            }

            case "ios_set_build_uses_encryption": {
                const { buildId, usesNonExemptEncryption } = args as { buildId: string; usesNonExemptEncryption: boolean };

                await apiPatchRequest(`/builds/${buildId}`, {
                    data: { type: "builds", id: buildId, attributes: { usesNonExemptEncryption } },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Encryption compliance set to ${usesNonExemptEncryption}` }, null, 2) }],
                };
            }

            // === BETA BUILD LOCALIZATIONS ===

            case "ios_update_beta_build_localization": {
                const { buildId, locale = "en-US", whatsNew } = args as { buildId: string; locale?: string; whatsNew: string };

                // First get existing localization or create one
                const token = generateToken();
                const existingResponse = await apiRequest<AppStoreResponse<{ id: string; attributes: { locale: string } }[]>>(
                    `/builds/${buildId}/betaBuildLocalizations`
                );

                const existing = existingResponse.data.find(l => l.attributes.locale === locale);

                if (existing) {
                    await apiPatchRequest(`/betaBuildLocalizations/${existing.id}`, {
                        data: { type: "betaBuildLocalizations", id: existing.id, attributes: { whatsNew } },
                    });
                } else {
                    const response = await fetch(`${BASE_URL}/betaBuildLocalizations`, {
                        method: "POST",
                        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                        body: JSON.stringify({
                            data: {
                                type: "betaBuildLocalizations",
                                attributes: { locale, whatsNew },
                                relationships: { build: { data: { type: "builds", id: buildId } } },
                            },
                        }),
                    });
                    if (!response.ok) throw new Error(`Failed to create localization: ${response.status}`);
                }

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `TestFlight what's new updated for ${locale}` }, null, 2) }],
                };
            }

            // === PRERELEASE VERSIONS ===

            case "ios_list_prerelease_versions": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { version: string; platform: string } }[]>>(
                    `/apps/${APP_ID}/preReleaseVersions?limit=20`
                );

                const versions = response.data.map(v => ({ versionId: v.id, ...v.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, prereleaseVersions: versions }, null, 2) }],
                };
            }

            // === RELEASE VERSION ===

            case "ios_release_version": {
                const { versionId } = args as { versionId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appStoreVersionReleaseRequests`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: {
                            type: "appStoreVersionReleaseRequests",
                            relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: versionId } } },
                        },
                    }),
                });

                if (!response.ok) throw new Error(`Failed to release: ${response.status} - ${await response.text()}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Version released to the App Store!" }, null, 2) }],
                };
            }

            // === AGE RATING ===

            case "ios_get_age_rating": {
                const { versionId } = args as { versionId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: any }>>(
                    `/appStoreVersions/${versionId}/ageRatingDeclaration`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, ageRating: response.data }, null, 2) }],
                };
            }

            // === APP CATEGORIES ===

            case "ios_get_app_categories": {
                const appInfosResponse = await apiRequest<AppStoreResponse<{ id: string }[]>>(`/apps/${APP_ID}/appInfos?limit=1`);
                if (!appInfosResponse.data.length) throw new Error("No app info found");

                const appInfoId = appInfosResponse.data[0].id;
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: any }>>(`/appInfos/${appInfoId}?include=primaryCategory,secondaryCategory,primarySubcategoryOne,primarySubcategoryTwo`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, appInfo: response.data, included: response.included }, null, 2) }],
                };
            }

            case "ios_list_available_categories": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { platforms: string[] } }[]>>(
                    `/appCategories?limit=200`
                );

                const categories = response.data.map(c => ({ categoryId: c.id, ...c.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalCategories: categories.length, categories }, null, 2) }],
                };
            }

            // === APP STORE EXPERIMENTS ===

            case "ios_list_experiments": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; state: string; reviewRequired: boolean; startDate?: string; endDate?: string } }[]>>(
                    `/apps/${APP_ID}/appStoreVersionExperimentsV2?limit=50`
                );

                const experiments = response.data.map(e => ({ experimentId: e.id, ...e.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, experiments }, null, 2) }],
                };
            }

            // === APP EVENTS ===

            case "ios_list_app_events": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { referenceName: string; badge?: string; eventState: string; purchaseRequirement?: string; primaryLocale: string } }[]>>(
                    `/apps/${APP_ID}/appEvents?limit=50`
                );

                const events = response.data.map(e => ({ eventId: e.id, ...e.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, totalEvents: events.length, appEvents: events }, null, 2) }],
                };
            }

            // === CUSTOM PRODUCT PAGES ===

            case "ios_list_custom_product_pages": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; url?: string; visible: boolean } }[]>>(
                    `/apps/${APP_ID}/appCustomProductPages?limit=50`
                );

                const pages = response.data.map(p => ({ pageId: p.id, ...p.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, customProductPages: pages }, null, 2) }],
                };
            }

            // === APP CLIPS ===

            case "ios_list_app_clips": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { bundleId: string } }[]>>(
                    `/apps/${APP_ID}/appClips?limit=50`
                );

                const clips = response.data.map(c => ({ clipId: c.id, ...c.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, appClips: clips }, null, 2) }],
                };
            }

            // === GAME CENTER ===

            case "ios_list_game_center_achievements": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { referenceName: string; vendorIdentifier: string; points: number; repeatable: boolean; showBeforeEarned: boolean; archived: boolean } }[]>>(
                    `/apps/${APP_ID}/gameCenterAchievements?limit=100`
                );

                const achievements = response.data.map(a => ({ achievementId: a.id, ...a.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, achievements }, null, 2) }],
                };
            }

            case "ios_list_game_center_leaderboards": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { referenceName: string; vendorIdentifier: string; defaultFormatter: string; archived: boolean } }[]>>(
                    `/apps/${APP_ID}/gameCenterLeaderboards?limit=100`
                );

                const leaderboards = response.data.map(l => ({ leaderboardId: l.id, ...l.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, leaderboards }, null, 2) }],
                };
            }

            // === REVIEW SUBMISSIONS ===

            case "ios_list_review_submissions": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { state: string; submitted: boolean; canceled: boolean } }[]>>(
                    `/apps/${APP_ID}/reviewSubmissions?limit=20`
                );

                const submissions = response.data.map(s => ({ submissionId: s.id, ...s.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, reviewSubmissions: submissions }, null, 2) }],
                };
            }

            // === APP STORE SUBMISSION ===

            case "ios_get_app_store_submission": {
                const { versionId } = args as { versionId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: any }>>(
                    `/appStoreVersions/${versionId}/appStoreVersionSubmission`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, submission: response.data }, null, 2) }],
                };
            }

            // === PROMOTIONAL OFFERS ===

            case "ios_list_promotional_offers": {
                const { subscriptionId } = args as { subscriptionId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { name: string; offerCode: string; duration: string; offerMode: string; numberOfPeriods: number } }[]>>(
                    `/subscriptions/${subscriptionId}/promotionalOffers?limit=50`
                );

                const offers = response.data.map(o => ({ offerId: o.id, ...o.attributes }));
                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, promotionalOffers: offers }, null, 2) }],
                };
            }

            // === BETA APP LOCALIZATION ===

            case "ios_update_beta_app_localization": {
                const { locale = "en-US", description, feedbackEmail, marketingUrl, privacyPolicyUrl, tvOsPrivacyPolicy } = args as {
                    locale?: string;
                    description?: string;
                    feedbackEmail?: string;
                    marketingUrl?: string;
                    privacyPolicyUrl?: string;
                    tvOsPrivacyPolicy?: string;
                };

                const token = generateToken();

                // First, get existing beta app localizations
                const listResponse = await fetch(`${BASE_URL}/apps/${APP_ID}/betaAppLocalizations`, {
                    headers: { Authorization: `Bearer ${token}` },
                });

                if (!listResponse.ok) throw new Error(`Failed to get beta app localizations: ${listResponse.status}`);

                const listData = await listResponse.json() as AppStoreResponse<{ id: string; attributes: { locale: string } }[]>;
                const existingLocalization = listData.data.find(l => l.attributes.locale === locale);

                // Build attributes object with only provided fields
                const attributes: Record<string, string> = {};
                if (description !== undefined) attributes.description = description;
                if (feedbackEmail !== undefined) attributes.feedbackEmail = feedbackEmail;
                if (marketingUrl !== undefined) attributes.marketingUrl = marketingUrl;
                if (privacyPolicyUrl !== undefined) attributes.privacyPolicyUrl = privacyPolicyUrl;
                if (tvOsPrivacyPolicy !== undefined) attributes.tvOsPrivacyPolicy = tvOsPrivacyPolicy;

                if (existingLocalization) {
                    // PATCH existing localization
                    const patchResponse = await fetch(`${BASE_URL}/betaAppLocalizations/${existingLocalization.id}`, {
                        method: "PATCH",
                        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                        body: JSON.stringify({
                            data: {
                                type: "betaAppLocalizations",
                                id: existingLocalization.id,
                                attributes,
                            },
                        }),
                    });

                    if (!patchResponse.ok) throw new Error(`Failed to update beta app localization: ${patchResponse.status} - ${await patchResponse.text()}`);

                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: true, message: `Beta app localization updated for ${locale}` }, null, 2) }],
                    };
                } else {
                    // POST new localization
                    const postResponse = await fetch(`${BASE_URL}/betaAppLocalizations`, {
                        method: "POST",
                        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                        body: JSON.stringify({
                            data: {
                                type: "betaAppLocalizations",
                                attributes: { locale, ...attributes },
                                relationships: {
                                    app: { data: { type: "apps", id: APP_ID } },
                                },
                            },
                        }),
                    });

                    if (!postResponse.ok) throw new Error(`Failed to create beta app localization: ${postResponse.status} - ${await postResponse.text()}`);

                    return {
                        content: [{ type: "text", text: JSON.stringify({ success: true, message: `Beta app localization created for ${locale}` }, null, 2) }],
                    };
                }
            }

            // === BETA APP REVIEW ===

            case "ios_submit_for_beta_review": {
                const { buildId } = args as { buildId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/betaAppReviewSubmissions`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: {
                            type: "betaAppReviewSubmissions",
                            relationships: { build: { data: { type: "builds", id: buildId } } },
                        },
                    }),
                });

                if (!response.ok) throw new Error(`Failed to submit for beta review: ${response.status} - ${await response.text()}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Build submitted for TestFlight beta review!" }, null, 2) }],
                };
            }

            // === DELETE BETA GROUP ===

            case "ios_delete_beta_group": {
                const { groupId } = args as { groupId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/betaGroups/${groupId}`, {
                    method: "DELETE",
                    headers: { Authorization: `Bearer ${token}` },
                });

                if (!response.ok) throw new Error(`Failed to delete beta group: ${response.status}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Beta group deleted" }, null, 2) }],
                };
            }

            // === ADD BUILD TO BETA GROUP ===

            case "ios_add_build_to_beta_group": {
                const { groupId, buildId } = args as { groupId: string; buildId: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/betaGroups/${groupId}/relationships/builds`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: [{ type: "builds", id: buildId }],
                    }),
                });

                if (!response.ok) throw new Error(`Failed to add build to group: ${response.status} - ${await response.text()}`);

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "Build added to beta group" }, null, 2) }],
                };
            }

            // === APP PREVIEW VIDEOS ===

            case "ios_list_app_previews": {
                const { localizationId } = args as { localizationId: string };

                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { previewType: string; videoUrl?: string; mimeType?: string; sourceFileChecksum?: string } }[]>>(
                    `/appStoreVersionLocalizations/${localizationId}/appPreviewSets?include=appPreviews&limit=50`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, appPreviewSets: response.data, included: response.included }, null, 2) }],
                };
            }

            // === CREATE APP STORE VERSION ===

            case "ios_create_app_store_version": {
                const { versionString, platform, releaseType = "MANUAL" } = args as { versionString: string; platform: string; releaseType?: string };

                const token = generateToken();
                const response = await fetch(`${BASE_URL}/appStoreVersions`, {
                    method: "POST",
                    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                    body: JSON.stringify({
                        data: {
                            type: "appStoreVersions",
                            attributes: { versionString, platform, releaseType },
                            relationships: { app: { data: { type: "apps", id: APP_ID } } },
                        },
                    }),
                });

                if (!response.ok) throw new Error(`Failed to create version: ${response.status} - ${await response.text()}`);
                const result = await response.json() as { data: { id: string } };

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: `Version ${versionString} created`, versionId: result.data.id }, null, 2) }],
                };
            }

            // === APP INFO LOCALIZATION UPDATE ===

            case "ios_update_app_info_localization": {
                const { localizationId, name, subtitle, privacyPolicyUrl, privacyChoicesUrl } = args as {
                    localizationId: string;
                    name?: string;
                    subtitle?: string;
                    privacyPolicyUrl?: string;
                    privacyChoicesUrl?: string;
                };

                const attributes: any = {};
                if (name) attributes.name = name;
                if (subtitle) attributes.subtitle = subtitle;
                if (privacyPolicyUrl) attributes.privacyPolicyUrl = privacyPolicyUrl;
                if (privacyChoicesUrl) attributes.privacyChoicesUrl = privacyChoicesUrl;

                await apiPatchRequest(`/appInfoLocalizations/${localizationId}`, {
                    data: { type: "appInfoLocalizations", id: localizationId, attributes },
                });

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, message: "App info localization updated", updated: attributes }, null, 2) }],
                };
            }

            // === EULA ===

            case "ios_get_eula": {
                const response = await apiRequest<AppStoreResponse<{ id: string; attributes: { agreementText?: string } }>>(
                    `/apps/${APP_ID}/endUserLicenseAgreement`
                );

                return {
                    content: [{ type: "text", text: JSON.stringify({ success: true, eula: response.data }, null, 2) }],
                };
            }

            default:
                return {
                    content: [
                        {
                            type: "text",
                            text: `Unknown tool: ${name}`,
                        },
                    ],
                    isError: true,
                };
        }
    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        return {
            content: [
                {
                    type: "text",
                    text: `Error: ${errorMessage}`,
                },
            ],
            isError: true,
        };
    }
});

async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("App Store Connect MCP Server running on stdio");
}

main().catch(console.error);
