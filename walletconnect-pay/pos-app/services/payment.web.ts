/**
 * Web (Expo): same Pay API calls as native via `payment-core`.
 * Do not re-export from `./payment` here — Metro resolves `./payment` to this file
 * on web and causes infinite re-export (maximum call stack exceeded).
 */
export { cancelPayment, getPaymentStatus, startPayment } from "./payment-core";
