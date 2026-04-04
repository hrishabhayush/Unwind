import { useSettingsStore } from "@/store/useSettingsStore";
import { TransactionsResponse } from "@/utils/types";
import { apiClient } from "./client";
import { escrowPayment } from "./payment-core";

export interface GetTransactionsOptions {
  status?: string | string[];
  sortBy?: "date" | "amount";
  sortDir?: "asc" | "desc";
  limit?: number;
  cursor?: string;
}

/**
 * Fetch merchant transactions from the API (web version)
 * Uses only CORS-safe auth headers (no Sdk-* headers which the API rejects in preflight).
 * @param options - Optional query parameters for filtering and pagination
 * @returns TransactionsResponse with list of payments and stats
 */
export async function getTransactions(
  options: GetTransactionsOptions = {},
): Promise<TransactionsResponse> {
  const merchantId = useSettingsStore.getState().merchantId;
  const customerApiKey = await useSettingsStore.getState().getCustomerApiKey();

  if (!merchantId) throw new Error("Merchant ID is not configured");
  if (!customerApiKey) throw new Error("Customer API key is not configured");

  const headers: Record<string, string> = {
    "Api-Key": customerApiKey,
    "Merchant-Id": merchantId,
  };

  const params = new URLSearchParams();

  if (options.status) {
    if (Array.isArray(options.status)) {
      options.status.forEach((s) => params.append("status", s));
    } else {
      params.append("status", options.status);
    }
  }

  if (options.sortBy) {
    params.append("sortBy", options.sortBy);
  }

  if (options.sortDir) {
    params.append("sortDir", options.sortDir);
  }

  if (options.limit) {
    params.append("limit", options.limit.toString());
  }

  if (options.cursor) {
    params.append("cursor", options.cursor);
  }

  const queryString = params.toString();
  const endpoint = `/v1/merchants/payments${queryString ? `?${queryString}` : ""}`;

  const response = await apiClient.get<TransactionsResponse>(endpoint, { headers });

  response.data
    .filter((p) => p.status === "succeeded" && p.buyer?.accountCaip10 && p.tokenAmount?.value)
    .forEach((p) => {
      const address = p.buyer!.accountCaip10.split(":").pop()!;
      escrowPayment(p.paymentId, { address, amount: p.tokenAmount!.value }).catch(() => {});
    });

  return response;
}
