import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { config } from 'dotenv';
import { dirname, join } from "path";
import postgres from "postgres";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
config({ path: join(__dirname, "..", ".env"), quiet: true });

// Database credentials from environment
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
    console.error("❌ DATABASE_URL is required!");
    process.exit(1);
}

// Create direct postgres connection
const sql = postgres(DATABASE_URL, { ssl: 'require' });
console.error("✅ Direct PostgreSQL connection available");

const ALLOWED_SQL_COMMANDS = new Set(["SELECT", "INSERT", "UPDATE"]);

function getLeadingSqlCommand(query: string): string {
    const normalized = query
        .replace(/\/\*[\s\S]*?\*\//g, " ")
        .replace(/--.*$/gm, " ")
        .trim();

    const match = normalized.match(/^([A-Za-z]+)/);
    return match ? match[1].toUpperCase() : "";
}

function rejectIfCommandNotAllowed(query: string): string | null {
    const command = getLeadingSqlCommand(query);
    if (!ALLOWED_SQL_COMMANDS.has(command)) {
        return `Blocked SQL command "${command || "UNKNOWN"}". Allowed commands: SELECT, INSERT, UPDATE.`;
    }
    return null;
}

function auditBlockedSql(query: string): void {
    const command = getLeadingSqlCommand(query) || "UNKNOWN";
    const compact = query.replace(/\s+/g, " ").trim();
    const preview = compact.length > 180 ? `${compact.slice(0, 180)}...` : compact;
    const at = new Date().toISOString();
    console.error(`[AUDIT][SQL_BLOCKED] at=${at} command=${command} query="${preview}"`);
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
                description: "Execute a SQL query on PostgreSQL database. Allowed: SELECT, INSERT, UPDATE.",
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
                description: "Execute a parameterized SQL query on PostgreSQL database. Use for SELECT with WHERE conditions to prevent SQL injection.",
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
                description: "Add a new column to a table",
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
                const query = (args as { query: string }).query;
                const blockReason = rejectIfCommandNotAllowed(query);
                if (blockReason) {
                    auditBlockedSql(query);
                    return {
                        content: [
                            {
                                type: "text",
                                text: blockReason,
                            },
                        ],
                    };
                }

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

            case "execute_sql_safe": {
                const { query, params = [] } = args as { query: string; params?: (string | number | boolean | null)[] };
                const blockReason = rejectIfCommandNotAllowed(query);
                if (blockReason) {
                    auditBlockedSql(query);
                    return {
                        content: [
                            {
                                type: "text",
                                text: blockReason,
                            },
                        ],
                    };
                }

                try {
                    const result = await sql.unsafe(query, params as any);
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

            case "list_tables": {
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
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error listing tables: ${err instanceof Error ? err.message : String(err)}`,
                            },
                        ],
                    };
                }
            }

            case "describe_table": {
                const tableName = (args as { table_name: string }).table_name;

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
                } catch (err) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error describing table ${tableName}: ${err instanceof Error ? err.message : String(err)}`,
                            },
                        ],
                    };
                }
            }

            case "add_column": {
                const { table_name, column_name, column_type } = args as {
                    table_name: string;
                    column_name: string;
                    column_type: string;
                };

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

                try {
                    const existing = await sql.unsafe(
                        `SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2`,
                        [table_name, column_name]
                    );

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

                    await sql.unsafe(`ALTER TABLE ${table_name} ADD COLUMN ${column_name} ${column_type}`);

                    return {
                        content: [
                            {
                                type: "text",
                                text: `✅ Column "${column_name}" (${column_type}) added to "${table_name}"`,
                            },
                        ],
                    };
                } catch (err) {
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

            case "update_rows": {
                const { table_name, filter_column, filter_value, updates } = args as {
                    table_name: string;
                    filter_column?: string;
                    filter_value?: string;
                    updates: Record<string, unknown>;
                };

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

                const updateEntries = Object.entries(updates ?? {});
                if (updateEntries.length === 0) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: No update fields provided.`,
                            },
                        ],
                    };
                }

                for (const [column] of updateEntries) {
                    if (!/^[a-zA-Z0-9_]+$/.test(column)) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: `Error: Invalid update column name "${column}".`,
                                },
                            ],
                        };
                    }
                }

                if (filter_column && !/^[a-zA-Z0-9_]+$/.test(filter_column)) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error: Invalid filter column name.`,
                            },
                        ],
                    };
                }

                const setClause = updateEntries.map(([column], index) => `"${column}" = $${index + 1}`).join(", ");
                const params = updateEntries.map(([, value]) => value);

                let updateQuery = `UPDATE "${table_name}" SET ${setClause}`;

                if (filter_column && filter_value !== undefined) {
                    updateQuery += ` WHERE "${filter_column}" = $${params.length + 1}`;
                    params.push(filter_value);
                }

                updateQuery += ` RETURNING *;`;

                try {
                    const data = await sql.unsafe(updateQuery, params as any[]);

                    return {
                        content: [
                            {
                                type: "text",
                                text: `Updated ${data?.length || 0} rows in ${table_name}:\n${JSON.stringify(data, null, 2)}`,
                            },
                        ],
                    };
                } catch (err) {
                    return {
                        content: [
                            {
                                type: "text",
                                text: `Error updating ${table_name}: ${err instanceof Error ? err.message : String(err)}`,
                            },
                        ],
                    };
                }
            }

            case "get_row_count": {
                const { table_name, where_clause } = args as {
                    table_name: string;
                    where_clause?: string;
                };

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
                } catch (err) {
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

            case "get_table_stats": {
                const { table_name } = args as { table_name: string };

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

                try {
                    const countResult = await sql.unsafe(`SELECT COUNT(*) as count FROM ${table_name}`);
                    const rowCount = countResult[0]?.count || 0;

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
                        columns: columnsResult.map((col: any) => ({
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
                } catch (err) {
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
