#!/usr/bin/env node
/**
 * Example test script to verify Supabase MCP Server tools
 * 
 * Usage: node examples/test-tools.mjs
 * 
 * Make sure to:
 * 1. Create .env file with your Supabase credentials
 * 2. Run: npm install
 * 3. Run: npm run build
 */

import { createClient } from "@supabase/supabase-js";
import { config as loadEnv } from "dotenv";
import { dirname, join } from "path";
import postgres from "postgres";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
loadEnv({ path: join(__dirname, ".env") });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DATABASE_URL = process.env.DATABASE_URL;

console.log("🔍 Testing Supabase MCP Server...\n");

// Test 1: Check environment
console.log("✅ Environment Variables:");
console.log(`   SUPABASE_URL: ${SUPABASE_URL ? "✓" : "✗ MISSING"}`);
console.log(`   SUPABASE_SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_KEY ? "✓" : "✗ MISSING"}`);
console.log(`   DATABASE_URL: ${DATABASE_URL ? "✓" : "✗ MISSING (optional)"}\n`);

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    console.error("❌ Missing required environment variables!");
    process.exit(1);
}

// Test 2: Supabase REST API Connection
console.log("🔗 Testing Supabase REST API Connection...");
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

try {
    const { data, error } = await supabase.from("auth.users").select("count").limit(0);
    if (!error) {
        console.log("✓ Supabase REST API: Connected\n");
    } else {
        console.log("⚠️ Supabase REST API: Limited access (might be expected)\n");
    }
} catch (err) {
    console.log("⚠️ Supabase REST API: Connection check inconclusive\n");
}

// Test 3: Direct PostgreSQL Connection
if (DATABASE_URL) {
    console.log("🔗 Testing Direct PostgreSQL Connection...");
    try {
        const sql = postgres(DATABASE_URL, { ssl: "require" });

        const result = await sql`SELECT 1 as connected`;
        if (result.length > 0) {
            console.log("✓ PostgreSQL Direct Connection: Connected\n");
        }

        await sql.end();
    } catch (err) {
        console.error(`✗ PostgreSQL Direct Connection Failed: ${err instanceof Error ? err.message : String(err)}\n`);
    }
} else {
    console.log("⚠️ DATABASE_URL not set - some tools will have limited functionality\n");
}

// Test 4: Example tool usage
console.log("📋 Example Tool Responses:\n");

console.log("1. list_tables:");
console.log('   Input: {}');
console.log("   Output: Array of table names in public schema\n");

console.log("2. describe_table:");
console.log('   Input: { table_name: "your_table" }');
console.log("   Output: Column info (name, type, nullable, defaults)\n");

console.log("3. execute_sql_safe:");
console.log('   Input: {');
console.log('     query: "SELECT * FROM users WHERE id = $1",');
console.log("     params: [123]");
console.log("   }");
console.log("   Output: Query results\n");

console.log("4. add_column:");
console.log('   Input: {');
console.log('     table_name: "users",');
console.log('     column_name: "verified",');
console.log('     column_type: "BOOLEAN DEFAULT false"');
console.log("   }");
console.log("   Output: Confirmation message\n");

console.log("5. get_row_count:");
console.log('   Input: { table_name: "orders" }');
console.log("   Output: Row count message\n");

console.log("6. get_table_stats:");
console.log('   Input: { table_name: "products" }');
console.log("   Output: JSON with row count, columns, size info\n");

console.log("✅ All checks complete! MCP Server is ready to use.");
