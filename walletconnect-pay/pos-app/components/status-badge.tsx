import { BorderRadius, Spacing } from "@/constants/spacing";
import { TransactionStatus } from "@/utils/types";
import { memo } from "react";
import { StyleSheet, View } from "react-native";
import { ThemedText } from "./themed-text";

type DisplayStatus = "completed" | "pending" | "failed";

interface StatusBadgeProps {
  status: TransactionStatus;
}

type ChipStyle = {
  backgroundColor: string;
  borderColor: string;
  textColor: string;
};

const STATUS_CHIP_STYLES: Record<DisplayStatus, ChipStyle> = {
  completed: {
    backgroundColor: "#30A46B",
    borderColor: "rgba(48, 164, 107, 0.3)",
    textColor: "#ffffff",
  },
  failed: {
    backgroundColor: "#DF4A34",
    borderColor: "rgba(223, 74, 52, 0.3)",
    textColor: "#ffffff",
  },
  pending: {
    backgroundColor: "#9A9A9A",
    borderColor: "rgba(255, 255, 255, 0.12)",
    textColor: "#ffffff",
  },
};

const STATUS_LABELS: Record<DisplayStatus, string> = {
  completed: "COMPLETED",
  pending: "PENDING",
  failed: "FAILED",
};

function mapToDisplayStatus(status: TransactionStatus): DisplayStatus {
  switch (status) {
    case "succeeded":
      return "completed";
    case "failed":
    case "expired":
    case "cancelled":
      return "failed";
    case "requires_action":
    case "processing":
    default:
      return "pending";
  }
}

function StatusBadgeBase({ status }: StatusBadgeProps) {
  const displayStatus = mapToDisplayStatus(status);
  const chipStyle = STATUS_CHIP_STYLES[displayStatus];
  const label = STATUS_LABELS[displayStatus];

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: chipStyle.backgroundColor,
          borderColor: chipStyle.borderColor,
        },
      ]}
    >
      <ThemedText
        fontSize={12}
        style={[styles.text, { color: chipStyle.textColor }]}
      >
        {label}
      </ThemedText>
    </View>
  );
}

export const StatusBadge = memo(StatusBadgeBase);

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: Spacing["spacing-3"],
    paddingVertical: 5,
    borderRadius: BorderRadius["full"],
    borderWidth: 1,
    alignSelf: "flex-start",
    alignItems: "center",
    justifyContent: "center",
  },
  text: {
    fontWeight: "600",
    letterSpacing: 0.4,
  },
});
