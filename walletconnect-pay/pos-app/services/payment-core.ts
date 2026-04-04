import {
  PaymentStatusResponse,
  StartPaymentRequest,
  StartPaymentResponse,
} from "@/utils/types";
import { apiClient, getApiHeaders } from "./client";

/**
 * Shared Pay API implementation (native + web).
 * Split out so `payment.web.ts` does not re-export from `./payment` (Metro would
 * resolve that back to `payment.web.ts` → stack overflow).
 */
export async function startPayment(
  request: StartPaymentRequest,
): Promise<StartPaymentResponse> {
  const headers = await getApiHeaders();
  return apiClient.post<StartPaymentResponse>("/v1/payments", request, {
    headers,
  });
}

export async function getPaymentStatus(
  paymentId: string,
): Promise<PaymentStatusResponse> {
  if (!paymentId?.trim()) {
    throw new Error("paymentId is required");
  }
  const headers = await getApiHeaders();
  return apiClient.get<PaymentStatusResponse>(
    `/v1/payments/${encodeURIComponent(paymentId)}/status`,
    { headers },
  );
}

export async function cancelPayment(paymentId: string): Promise<void> {
  if (!paymentId?.trim()) {
    throw new Error("paymentId is required");
  }
  const headers = await getApiHeaders();
  await apiClient.post(
    `/v1/payments/${encodeURIComponent(paymentId)}/cancel`,
    {},
    { headers },
  );
}

export async function refundPayment(
  paymentId: string,
): Promise<{ txHash: string; payer: string; amount: string }> {
  if (!paymentId?.trim()) {
    throw new Error("paymentId is required");
  }
  const merchantApiUrl = (
    process.env.EXPO_PUBLIC_SERVER_URL ?? ""
  ).replace(/\/+$/, "");
  const res = await fetch(
    `${merchantApiUrl}/api/payments/${encodeURIComponent(paymentId)}/refund`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    },
  );
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      (err as { error?: string }).error ?? `Refund failed: ${res.status}`,
    );
  }
  return res.json();
}
