import { providerStatus } from "@/lib/ai/provider";

// Tells the UI whether a real provider is configured (a key in the environment). The key itself is never exposed.
export async function GET() {
  return Response.json(providerStatus());
}
