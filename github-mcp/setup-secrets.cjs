const { Octokit } = require("@octokit/rest");
const sodium = require("libsodium-wrappers");
const fs = require("fs");
const path = require("path");

// Load environment variables
require("dotenv").config({ path: path.join(__dirname, ".env") });

const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_REPO_OWNER = process.env.GITHUB_REPO_OWNER || "lakisa-code";
const GITHUB_REPO_NAME = process.env.GITHUB_REPO_NAME || "gavra_android";

if (!GITHUB_TOKEN) {
    console.error("❌ GITHUB_TOKEN nije postavljen u .env");
    process.exit(1);
}

const octokit = new Octokit({ auth: GITHUB_TOKEN });

function readValueFromFile(filePath) {
    if (!filePath) return "";
    const resolvedPath = path.isAbsolute(filePath)
        ? filePath
        : path.join(__dirname, filePath);

    if (!fs.existsSync(resolvedPath)) {
        throw new Error(`Fajl ne postoji: ${resolvedPath}`);
    }

    return fs.readFileSync(resolvedPath, "utf8").trim();
}

function getSecretValue(envKey, fileEnvKey) {
    const fromEnv = process.env[envKey]?.trim();
    if (fromEnv) return fromEnv;

    const filePath = process.env[fileEnvKey]?.trim();
    if (filePath) return readValueFromFile(filePath);

    return "";
}

const secrets = {
    GOOGLE_PLAY_KEY_B64: getSecretValue("GOOGLE_PLAY_KEY_B64", "GOOGLE_PLAY_KEY_B64_FILE"),
    ANDROID_KEYSTORE_B64: getSecretValue("ANDROID_KEYSTORE_B64", "ANDROID_KEYSTORE_B64_FILE"),
    ANDROID_KEYSTORE_PASSWORD: getSecretValue("ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEYSTORE_PASSWORD_FILE"),
    ANDROID_KEY_PASSWORD: getSecretValue("ANDROID_KEY_PASSWORD", "ANDROID_KEY_PASSWORD_FILE"),
    ANDROID_KEY_ALIAS: process.env.ANDROID_KEY_ALIAS?.trim() || "",
};

const missingSecrets = Object.entries(secrets)
    .filter(([, value]) => !value)
    .map(([key]) => key);

if (missingSecrets.length > 0) {
    console.error(`❌ Nedostaju obavezne vrednosti: ${missingSecrets.join(", ")}`);
    console.error("➡️ Postavi ih u .env (ili *_FILE varijable za čitanje iz fajla)");
    process.exit(1);
}

async function encryptSecret(publicKey, secretValue) {
    await sodium.ready;

    const binaryString = Buffer.from(publicKey, "base64").toString("binary");
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }

    const encrypted = sodium.crypto_box_seal(secretValue, bytes);
    return Buffer.from(encrypted).toString("base64");
}

async function getPublicKey() {
    try {
        const response = await octokit.rest.actions.getRepoPublicKey({
            owner: GITHUB_REPO_OWNER,
            repo: GITHUB_REPO_NAME,
        });
        return response.data;
    } catch (error) {
        console.error("❌ Greška pri učitavanju GitHub javnog ključa:", error.message);
        throw error;
    }
}

async function setSecret(publicKey, secretName, secretValue) {
    try {
        const encrypted = await encryptSecret(publicKey.key, secretValue);

        await octokit.rest.actions.createOrUpdateRepoSecret({
            owner: GITHUB_REPO_OWNER,
            repo: GITHUB_REPO_NAME,
            secret_name: secretName,
            encrypted_value: encrypted,
            key_id: publicKey.key_id,
        });

        console.log(`✅ Secret postavljeno: ${secretName}`);
    } catch (error) {
        console.error(`❌ Greška pri postavljanju ${secretName}:`, error.message);
        throw error;
    }
}

async function main() {
    try {
        console.log("🔐 GitHub Secrets Setup - Počinje postavljanje tajni...\n");
        console.log(`📦 Repository: ${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}\n`);

        const publicKey = await getPublicKey();
        console.log(`🔑 Učitan javni ključ: ${publicKey.key_id}\n`);

        console.log("📝 Postavljam tajne:\n");

        for (const [name, value] of Object.entries(secrets)) {
            await setSecret(publicKey, name, value);
        }

        console.log("\n✨ Sve tajne su uspešno postavljene!");
        console.log("\n🚀 GitHub Actions workflow je sada spreman za pokretanje.");

    } catch (error) {
        console.error("\n❌ Postavka tajni je neuspešna:", error);
        process.exit(1);
    }
}

main();
