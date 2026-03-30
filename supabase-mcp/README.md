# 🛠️ Supabase Direct MCP Server

A Model Context Protocol (MCP) server for direct PostgreSQL database access to Supabase projects.

## Features

- ✅ **Direct PostgreSQL Connection** - Full SQL support via `DATABASE_URL`
- ✅ **Safe Parameterized Queries** - Prevent SQL injection with `execute_sql_safe`
- ✅ **Table Management** - List, describe, and get statistics about tables
- ✅ **Safe Column Operations** - Add columns with validation
- ✅ **Row Operations** - Count rows, update rows, get comprehensive stats
- ✅ **Automatic Fallback** - Falls back to Supabase REST API if direct connection fails

## Quick Start

### 1. Setup Environment Variables

Copy `.env.example` to `.env` and fill in your Supabase credentials:

```bash
cp .env.example .env
```

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
DATABASE_URL=postgresql://postgres.xxx:password@aws-0-region.pooler.supabase.com:6543/postgres
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Build

```bash
npm run build
```

### 4. Run the MCP Server

```bash
npm start
```

Or use it with Claude/other MCP clients by pointing to:
```
node dist/index.js
```

## Available Tools

### 1. `list_tables`
List all tables in the public schema.

```
tool: list_tables
params: {}
```

### 2. `describe_table`
Get detailed column information for a table.

```
tool: describe_table
params:
  table_name: "users"
```

### 3. `execute_sql`
Execute any SQL query (SELECT, INSERT, UPDATE, DELETE).

```
tool: execute_sql
params:
  query: "SELECT * FROM users WHERE id = 1"
```

### 4. `execute_sql_safe` ⭐ **RECOMMENDED**
Execute SQL with parameterized queries to prevent SQL injection.

```
tool: execute_sql_safe
params:
  query: "SELECT * FROM users WHERE id = $1 AND email = $2"
  params: [123, "user@example.com"]
```

### 5. `add_column`
Add a new column to a table safely.

```
tool: add_column
params:
  table_name: "users"
  column_name: "verified"
  column_type: "BOOLEAN DEFAULT false"
```

### 6. `get_row_count`
Get the number of rows in a table (optionally filtered).

```
tool: get_row_count
params:
  table_name: "orders"
  where_clause: "status = 'pending'" # optional
```

### 7. `get_table_stats`
Get comprehensive statistics about a table.

```
tool: get_table_stats
params:
  table_name: "products"
```

Response includes:
- Row count
- Column count and details
- Table size
- Index sizes

### 8. `update_rows`
Update rows in a table.

```
tool: update_rows
params:
  table_name: "users"
  filter_column: "id"
  filter_value: "123"
  updates:
    last_login: "2026-03-30T10:00:00Z"
    status: "active"
```

## Security Notes

⚠️ **Important Security Practices:**

1. **Never commit `.env` file** - Add it to `.gitignore`
2. **Use `execute_sql_safe`** - Always use parameterized queries when possible
3. **Validate table names** - The server validates table names to prevent SQL injection in `describe_table` and `add_column`
4. **Service Role Key** - Has full database access, keep it secure
5. **DATABASE_URL** - Contains credentials, never expose it

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | ✅ Yes | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ Yes | Service role key with full access |
| `DATABASE_URL` | ❌ Optional | PostgreSQL connection string for full SQL support |

### Getting Your Credentials

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Go to **Settings > API**
4. Find:
   - `SUPABASE_URL` under "Project URL"
   - `SUPABASE_SERVICE_ROLE_KEY` under "Service role key"
5. For `DATABASE_URL`, go to **Settings > Database > Connection Pooling** and get the URI

## Development

```bash
# Build TypeScript
npm run build

# Run in development
npm start

# Type checking
npm run build
```

## Troubleshooting

### Error: "SUPABASE_URL is required"
- Make sure `.env` file exists and has `SUPABASE_URL` set

### Error: "DATABASE_URL not configured"
- Some tools require `DATABASE_URL` for direct database access
- Set `DATABASE_URL` in `.env` to enable all features

### SQL Injection Errors
- Use `execute_sql_safe` with parameters instead of string concatenation
- Always validate and sanitize table/column names

### Connection Refused
- Check that `DATABASE_URL` is correct
- Ensure your Supabase project is running
- Check IP whitelist in Supabase settings

## License

MIT
