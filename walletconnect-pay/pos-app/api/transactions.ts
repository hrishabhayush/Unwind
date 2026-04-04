import type { VercelRequest, VercelResponse } from "@vercel/node";

const API_BASE_URL = process.env.EXPO_PUBLIC_API_URL;
const MERCHANT_PORTAL_API_KEY = process.env.EXPO_PUBLIC_MERCHANT_PORTAL_API_KEY;

/**
 * Vercel Serverless Function to proxy transaction list requests
 * This avoids CORS issues by making the request server-side
 *
 * GET /api/transactions?status=...&limit=...&cursor=...
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Only allow GET requests
  if (req.method !== "GET") {
    return res.status(405).json({ message: "Method not allowed" });
  }

  try {
    // Extract merchant ID from request headers
    const merchantId = req.headers["x-merchant-id"] as string;

    if (!merchantId) {
      return res.status(400).json({
        message: "Missing required header: x-merchant-id",
      });
    }

    if (!API_BASE_URL) {
      return res.status(500).json({
        message: "API_BASE_URL is not configured",
      });
    }

    if (!MERCHANT_PORTAL_API_KEY) {
      return res.status(500).json({
        message: "MERCHANT_PORTAL_API_KEY is not configured",
      });
    }

    // Build query string from request query params
    const params = new URLSearchParams();
    const { status, sortBy, sortDir, limit, cursor, startTs, endTs } = req.query;

    // Handle status (can be array for multiple status filters)
    if (status) {
      if (Array.isArray(status)) {
        status.forEach((s) => params.append("status", s));
      } else {
        params.append("status", status);
      }
    }
    if (sortBy && typeof sortBy === "string") {
      params.append("sortBy", sortBy);
    }
    if (sortDir && typeof sortDir === "string") {
      params.append("sortDir", sortDir);
    }
    if (limit && typeof limit === "string") {
      params.append("limit", limit);
    }
    if (cursor && typeof cursor === "string") {
      params.append("cursor", cursor);
    }
    if (startTs && typeof startTs === "string") {
      params.append("startTs", startTs);
    }
    if (endTs && typeof endTs === "string") {
      params.append("endTs", endTs);
    }

    const queryString = params.toString();
    const normalizedBaseUrl = API_BASE_URL.replace(/\/+$/, "");
    const endpoint = `/merchants/payments${queryString ? `?${queryString}` : ""}`;

    const response = await fetch(`${normalizedBaseUrl}${endpoint}`, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "Api-Key": MERCHANT_PORTAL_API_KEY,
        "Merchant-Id": merchantId,
      },
    });

    const data = await response.json();

    if (!response.ok) {
      return res.status(response.status).json(data);
    }

    return res.status(200).json(data);
  } catch (error) {
    console.error("Transactions proxy error:", error);
    return res.status(500).json({
      message: error instanceof Error ? error.message : "Internal server error",
    });
  }
}
