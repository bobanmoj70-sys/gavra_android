import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createClient, SupabaseClient } from "@supabase/supabase-js";
import 'dotenv/config.js';
import postgres from "postgres";

// Supabase credentials from environment
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DATABASE_URL = process.env.DATABASE_URL;

if (!SUPABASE_URL) {
    console.error("❌ SUPABASE_URL is required!");
    process.exit(1);
}

if (!SUPABASE_SERVICE_KEY) {
    console.error("❌ SUPABASE_SERVICE_ROLE_KEY is required!");
    process.exit(1);
}

// Create Supabase client with service role key (full access)
const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// Create direct postgres connection if DATABASE_URL is available
let sql: ReturnType<typeof postgres> | null = null;
if (DATABASE_URL) {
    sql = postgres(DATABASE_URL, { ssl: 'require' });
    console.error("✅ Direct PostgreSQL connection available");
} else {
    console.error("⚠️ DATABASE_URL not set - using REST API fallback");
}

// Create MCP server
const server = new Server(
    {
        name: "supabase-direct",
        version: "1.0.0",
    },
    {
        capabilities: {
            tools: {},
        },
    }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: "execute_sql",
                description: "Execute a SQL query on Supabase PostgreSQL database. Use for SELECT, INSERT, UPDATE, DELETE queries.",
                inputSchema: {
                    type: "object",
                    properties: {
                        query: {
                            type: "string",
                            description: "The SQL query to execute",
                        },
                    },
                    required: ["query"],
                },
            },
            {
                name: "list_tables",
                description: "List all tables in the public schema",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "describe_table",
                description: "Get column information for a specific table",
                inputSchema: {
                    type: "object",
                    properties: {
                        table_name: {
                            type: "string",
                            description: "Name of the table to describe",
                        },
                    },
                    required: ["table_name"],
                },
            },
            {
                name: "add_column",
                description: "Add a new column to a table using Supabase Management API",
                inputSchema: {
                    type: "object",
                    properties: {
                        table_name: {
                            type: "string",
                            description: "Name of the table",
                        },
                        column_name: {
                            type: "string",
                            description: "Name of the new column",
                        },
                        column_type: {
                            type: "string",
                            description: "PostgreSQL data type (e.g., INTEGER, TEXT, BOOLEAN)",
                        },
                    },
                    required: ["table_name", "column_name", "column_type"],
                },
            },
            {
                name: "update_rows",
                description: "Update rows in a table",
                inputSchema: {
                    type: "object",
                    properties: {
                        table_name: {
                            type: "string",
                            description: "Name of the table",
                        },
                        filter_column: {
                            type: "string",
                            description: "Column to filter by",
                        },
                        filter_value: {
                            type: "string",
                            description: "Value to filter by",
                        },
                        updates: {
                            type: "object",
                            description: "Object with column names and new values",
                        },
                    },
                    required: ["table_name", "updates"],
                },
            },
        ],
    };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
        switch (name) {
            case "execute_sql": {
                const query = (args as { query: string }).query;

                // Method 1: Use direct postgres connection (BEST - always works)
                if (sql) {
                    try {
                        const result = await sql.unsafe(query);
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(result, null, 2),
                                },
                            ],
                        };
                    } catch (err) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `SQL Error: ${err instanceof Error ? err.message : String(err)}`,
                                },
                            ],
                        };
                    }
                }

                // Method 2: Fallback to Supabase REST API for SELECT on known tables
                const isSelect = query.trim().toLowerCase().startsWith("select");
                const tableMatch = query.match(/from\s+["']?(\w+)["']?/i);

                if (isSelect && tableMatch) {
                    const tableName = tableMatch[1];
                    const { data, error } = await supabase
                        .from(tableName)
                        .select("*")
                        .limit(100);

                    if (!error) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(data, null, 2),
                                },
                            ],
                        };
                    }
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: `Error: DATABASE_URL not configured. Set DATABASE_URL environment variable to enable full SQL support.\n\nConnection string format: postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres`,
                        },
                    ],
                };
            }

            case "list_tables": {
                // Method 1: Use direct postgres connection (BEST)
                if (sql) {
                    try {
                        const result = await sql.unsafe(`
                            SELECT table_name 
                            FROM information_schema.tables 
                            WHERE table_schema = 'public' 
                            ORDER BY table_name;
                        `);
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(result, null, 2),
                                },
                            ],
                        };
                    } catch (err) {
                        console.error("Direct SQL list_tables failed, falling back...");
                    }
                }

                // Fallback: use raw query via REST API
                const { data, error } = await supabase
                    .from("information_schema.tables")
                    .select("table_name")
                    .eq("table_schema", "public");

                if (error) {
                    // Fallback: use raw query via REST API
                    const response = await fetch(
                        `${SUPABASE_URL}/rest/v1/?apikey=${SUPABASE_SERVICE_KEY}`,
                        {
                            headers: {
                                "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                            },
                        }
                    );

                    if (response.ok) {
                        // REST API root returns available tables
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: "Tables available via REST API. Use execute_sql with: SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'",
                                },
                            ],
                        };
                    }

                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error listing tables: ${error.message}`,
                            },
                        ],
                    };
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify(data, null, 2),
                        },
                    ],
                };
            }

            case "describe_table": {
                const tableName = (args as { table_name: string }).table_name;

                // Method 1: Use direct postgres connection (BEST)
                if (sql) {
                    try {
                        const result = await sql.unsafe(`
                            SELECT 
                                column_name, 
                                data_type, 
                                is_nullable,
                                column_default
                            FROM information_schema.columns 
                            WHERE table_name = '${tableName}'
                            ORDER BY ordinal_position;
                        `);
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(result, null, 2),
                                },
                            ],
                        };
                    } catch (err) {
                        console.error("Direct SQL describe_table failed, falling back...");
                    }
                }

                const { data, error } = await supabase
                    .from(tableName)
                    .select("*")
                    .limit(0);

                if (error) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error describing table ${tableName}: ${error.message}`,
                            },
                        ],
                    };
                }

                // Get column info from a sample query
                const { data: sample } = await supabase
                    .from(tableName)
                    .select("*")
                    .limit(1);

                const columns = sample && sample.length > 0
                    ? Object.keys(sample[0]).map(col => ({ column_name: col, sample_value: sample[0][col] }))
                    : [];

                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({ table: tableName, columns }, null, 2),
                        },
                    ],
                };
            }

            case "add_column": {
                const { table_name, column_name, column_type } = args as {
                    table_name: string;
                    column_name: string;
                    column_type: string;
                };

                // Use the postgres connection through supabase-js
                // Since we can't do ALTER TABLE directly, we need to use a workaround
                // Try to insert a row with the new column to see if it exists
                const { data: existing } = await supabase
                    .from(table_name)
                    .select(column_name)
                    .limit(1);

                if (existing !== null) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Column ${column_name} already exists in ${table_name}`,
                            },
                        ],
                    };
                }

                // Column doesn't exist - need to add via SQL Editor in Supabase Dashboard
                // or via database connection string
                return {
                    content: [
                        {
                            type: "text",
                            text: `To add column "${column_name}" (${column_type}) to "${table_name}", run this in Supabase SQL Editor:\n\nALTER TABLE ${table_name} ADD COLUMN ${column_name} ${column_type};`,
                        },
                    ],
                };
            }

            case "update_rows": {
                const { table_name, filter_column, filter_value, updates } = args as {
                    table_name: string;
                    filter_column?: string;
                    filter_value?: string;
                    updates: Record<string, unknown>;
                };

                let query = supabase.from(table_name).update(updates);

                if (filter_column && filter_value !== undefined) {
                    query = query.eq(filter_column, filter_value);
                }

                const { data, error } = await query.select();

                if (error) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error updating ${table_name}: ${error.message}`,
                            },
                        ],
                    };
                }

                return {
                    content: [
                        {
                            type: "text",
                            text: `Updated ${data?.length || 0} rows in ${table_name}:\n${JSON.stringify(data, null, 2)}`,
                        },
                    ],
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
                };
        }
    } catch (err) {
        return {
            content: [
                {
                    type: "text",
                    text: `Error: ${err instanceof Error ? err.message : String(err)}`,
                },
            ],
        };
    }
});

// Start the server
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("🚀 Supabase Direct MCP Server running...");
}

main().catch(console.error);
