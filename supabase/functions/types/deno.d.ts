/// <reference no-default-lib="true" />
/// <reference lib="deno.window" />
/// <reference lib="dom" />
/// <reference lib="es2022" />

// Complete Deno environment types for Supabase Edge Functions
declare global {
  // Standard JavaScript globals
  const console: Console;
  const JSON: JSON;
  const Object: ObjectConstructor;
  const String: StringConstructor;
  const Error: ErrorConstructor;
  const Response: new (body?: BodyInit | null, init?: ResponseInit) => Response;
  const Request: new (input: RequestInfo | URL, init?: RequestInit) => Request;

  // Deno namespace and environment
  namespace Deno {
    interface Env {
      get(key: string): string | undefined;
    }
    const env: Env;
  }

  const Deno: {
    env: {
      get(key: string): string | undefined;
    };
  };
}

// Module declarations for Deno URL imports
declare module "https://deno.land/std@0.168.0/http/server.ts" {
  export function serve(handler: (request: Request) => Response | Promise<Response>, options?: any): void;
}

declare module "https://esm.sh/@supabase/supabase-js@2.38.4" {
  export function createClient(url: string, key: string, options?: any): any;
}

export { };
