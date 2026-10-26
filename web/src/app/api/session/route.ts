import type { NextRequest } from "next/server";
import { handleSessionRequest } from "@/lib/server/session-handler";

/** Login / refresh / logout proxy. See src/lib/server/session-handler.ts. */
export async function POST(req: NextRequest) {
  return handleSessionRequest(req);
}
