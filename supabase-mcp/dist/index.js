import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import { createClient } from "@supabase/supabase-js";
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
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// Create direct postgres connection if DATABASE_URL is available
let sql = null;
if (DATABASE_URL) {
    sql = postgres(DATABASE_URL, { ssl: 'require' });
    console.error("✅ Direct PostgreSQL connection available");
}
else {
    console.error("⚠️ DATABASE_URL not set - using REST API fallback");
}
// Create MCP server
const server = new Server({
    name: "supabase-direct",
    version: "1.0.0",
}, {
    capabilities: {
        tools: {},
    },
});
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
                name: "execute_sql_safe",
                description: "Execute a parameterized SQL query on Supabase PostgreSQL database. Use for SELECT with WHERE conditions to prevent SQL injection.",
                inputSchema: {
                    type: "object",
                    properties: {
                        query: {
                            type: "string",
                            description: "The SQL query to execute with $1, $2, etc. for parameters",
                        },
                        params: {
                            type: "array",
                            description: "Array of parameter values to safely substitute",
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
            {
                name: "get_row_count",
                description: "Get the number of rows in a table",
                inputSchema: {
                    type: "object",
                    properties: {
                        table_name: {
                            type: "string",
                            description: "Name of the table",
                        },
                        where_clause: {
                            type: "string",
                            description: "Optional WHERE clause condition (e.g., 'id > 10')",
                        },
                    },
                    required: ["table_name"],
                },
            },
            {
                name: "get_table_stats",
                description: "Get detailed statistics about a table (row count, size, columns, etc.)",
                inputSchema: {
                    type: "object",
                    properties: {
                        table_name: {
                            type: "string",
                            description: "Name of the table",
                        },
                    },
                    required: ["table_name"],
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
                const query = args.query;
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
                    }
                    catch (err) {
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
            case "execute_sql_safe": {
                const { query, params = [] } = args;
                if (!sql) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: DATABASE_URL not configured. Parameterized queries require direct database connection.`,
                            },
                        ],
                    };
                }
                try {
                    const result = await sql.unsafe(query, params);
                    return {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify(result, null, 2),
                            },
                        ],
                    };
                }
                catch (err) {
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
                    }
                    catch (err) {
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
                    const response = await fetch(`${SUPABASE_URL}/rest/v1/?apikey=${SUPABASE_SERVICE_KEY}`, {
                        headers: {
                            "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
                        },
                    });
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
                const tableName = args.table_name;
                // Validate table name to prevent SQL injection
                if (!/^[a-zA-Z0-9_]+$/.test(tableName)) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: Invalid table name. Only alphanumeric characters and underscores allowed.`,
                            },
                        ],
                    };
                }
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
                            WHERE table_name = $1
                            ORDER BY ordinal_position;
                        `, [tableName]);
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(result, null, 2),
                                },
                            ],
                        };
                    }
                    catch (err) {
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
                const { table_name, column_name, column_type } = args;
                // Validate input to prevent SQL injection
                if (!/^[a-zA-Z0-9_]+$/.test(table_name) || !/^[a-zA-Z0-9_]+$/.test(column_name)) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: Invalid table or column name. Only alphanumeric characters and underscores allowed.`,
                            },
                        ],
                    };
                }
                if (sql) {
                    try {
                        // Check if column exists
                        const existing = await sql.unsafe(`SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2`, [table_name, column_name]);
                        if (existing.length > 0) {
                            return {
                                content: [
                                    {
                                        type: "text",
                                        text: `Column ${column_name} already exists in ${table_name}`,
                                    },
                                ],
                            };
                        }
                        // Add the column
                        await sql.unsafe(`ALTER TABLE ${table_name} ADD COLUMN ${column_name} ${column_type}`);
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `✅ Column "${column_name}" (${column_type}) added to "${table_name}"`,
                                },
                            ],
                        };
                    }
                    catch (err) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `Error adding column: ${err instanceof Error ? err.message : String(err)}`,
                                },
                            ],
                        };
                    }
                }
                // Fallback when no direct connection
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
                const { table_name, filter_column, filter_value, updates } = args;
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
            case "get_row_count": {
                const { table_name, where_clause } = args;
                // Validate table name
                if (!/^[a-zA-Z0-9_]+$/.test(table_name)) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: Invalid table name. Only alphanumeric characters and underscores allowed.`,
                            },
                        ],
                    };
                }
                if (sql) {
                    try {
                        let query = `SELECT COUNT(*) as count FROM ${table_name}`;
                        if (where_clause) {
                            query += ` WHERE ${where_clause}`;
                        }
                        query += `;`;
                        const result = await sql.unsafe(query);
                        const count = result[0]?.count || 0;
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `Table "${table_name}" has ${count} rows${where_clause ? ` matching "${where_clause}"` : ""}`,
                                },
                            ],
                        };
                    }
                    catch (err) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `Error counting rows: ${err instanceof Error ? err.message : String(err)}`,
                                },
                            ],
                        };
                    }
                }
                return {
                    content: [
                        {
                            type: "text",
                            text: `Error: DATABASE_URL not configured. Cannot count rows without direct database connection.`,
                        },
                    ],
                };
            }
            case "get_table_stats": {
                const { table_name } = args;
                // Validate table name
                if (!/^[a-zA-Z0-9_]+$/.test(table_name)) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: Invalid table name. Only alphanumeric characters and underscores allowed.`,
                            },
                        ],
                    };
                }
                if (sql) {
                    try {
                        // Get row count
                        const countResult = await sql.unsafe(`SELECT COUNT(*) as count FROM ${table_name}`);
                        const rowCount = countResult[0]?.count || 0;
                        // Get column info
                        const columnsResult = await sql.unsafe(`
                            SELECT 
                                column_name, 
                                data_type, 
                                is_nullable,
                                column_default
                            FROM information_schema.columns 
                            WHERE table_name = $1
                            ORDER BY ordinal_position;
                        `, [table_name]);
                        // Get table size
                        const sizeResult = await sql.unsafe(`
                            SELECT 
                                pg_size_pretty(pg_total_relation_size($1)) as size,
                                pg_size_pretty(pg_relation_size($1)) as table_size
                            FROM (SELECT NULL::text) t;
                        `, [table_name]);
                        const stats = {
                            table_name,
                            row_count: rowCount,
                            column_count: columnsResult.length,
                            columns: columnsResult.map((col) => ({
                                name: col.column_name,
                                type: col.data_type,
                                nullable: col.is_nullable === 'YES',
                                default: col.column_default,
                            })),
                            size: sizeResult[0]?.size || 'N/A',
                            table_size: sizeResult[0]?.table_size || 'N/A',
                        };
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify(stats, null, 2),
                                },
                            ],
                        };
                    }
                    catch (err) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `Error getting table stats: ${err instanceof Error ? err.message : String(err)}`,
                                },
                            ],
                        };
                    }
                }
                return {
                    content: [
                        {
                            type: "text",
                            text: `Error: DATABASE_URL not configured. Cannot get table stats without direct database connection.`,
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
    }
    catch (err) {
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
