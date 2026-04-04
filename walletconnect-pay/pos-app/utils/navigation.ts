import { Colors } from "@/constants/theme";
import { Href, router } from "expo-router";

/** Routes that show the brand logo centered instead of a text title */
export const isLogoScreen = (routeName: string): boolean =>
  routeName === "index" || routeName === "payment-success";

export const shouldCenterHeaderTitle = isLogoScreen;

const SCREEN_TITLES: Record<string, string> = {
  amount: "New Payment",
  scan: "Awaiting Payment",
  "payment-failure": "Payment Failed",
  settings: "Settings",
  activity: "Activity",
  logs: "Logs",
};

export const getScreenTitle = (routeName: string): string =>
  SCREEN_TITLES[routeName] ?? "";

export const getHeaderBackgroundColor = (
  routeName: string,
): keyof typeof Colors.light | keyof typeof Colors.dark => {
  return routeName === "payment-success" ? "bg-payment-success" : "bg-primary";
};

export const getHeaderTintColor = (
  routeName: string,
): keyof typeof Colors.light | keyof typeof Colors.dark => {
  return routeName === "payment-success"
    ? "text-payment-success"
    : "text-primary";
};

export const resetNavigation = (href?: Href) => {
  router.dismissAll();
  router.replace("/");
  if (href) {
    router.navigate(href);
  }
};
