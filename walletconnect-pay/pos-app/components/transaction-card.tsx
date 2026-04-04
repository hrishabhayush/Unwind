import { BorderRadius, Spacing } from "@/constants/spacing";
import { useTheme } from "@/hooks/use-theme-color";
import { formatCardDateTime } from "@/utils/misc";
import { formatFiatAmount } from "@/utils/currency";
import { PaymentRecord, PaymentStatus } from "@/utils/types";
import { memo } from "react";
import { StyleProp, StyleSheet, View, ViewStyle } from "react-native";
import { Button } from "./button";
import { StatusBadge } from "./status-badge";
import { ThemedText } from "./themed-text";

interface TransactionCardProps {
  payment: PaymentRecord;
  onPress: () => void;
  style?: StyleProp<ViewStyle>;
}

function getStatusAccentColor(status: PaymentStatus): string {
  switch (status) {
    case "succeeded":
      return "#30A46B";
    case "failed":
    case "expired":
    case "cancelled":
      return "#DF4A34";
    case "requires_action":
    case "processing":
    default:
      return "#4F4F4F";
  }
}

function TransactionCardBase({
  payment,
  onPress,
  style,
}: TransactionCardProps) {
  const theme = useTheme();
  const accentColor = getStatusAccentColor(payment.status);

  return (
    <Button
      onPress={onPress}
      style={[
        styles.container,
        {
          backgroundColor: theme["foreground-primary"],
          borderBottomColor: theme["border-primary"],
        },
        style,
      ]}
    >
      <View
        style={[styles.accentBorder, { backgroundColor: accentColor }]}
      />
      <View style={styles.leftContent}>
        <ThemedText
          fontSize={18}
          lineHeight={24}
          color="text-primary"
          style={styles.amountText}
        >
          {formatFiatAmount(payment.fiatAmount ? parseInt(payment.fiatAmount.value) : undefined, payment.fiatAmount?.unit)}
        </ThemedText>
        <ThemedText fontSize={12} lineHeight={16} color="text-secondary">
          {formatCardDateTime(payment.createdAt)}
        </ThemedText>
      </View>
      <StatusBadge status={payment.status} />
    </Button>
  );
}

export const TransactionCard = memo(TransactionCardBase);

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: Spacing["spacing-4"],
    paddingRight: Spacing["spacing-5"],
    paddingLeft: 0,
    borderRadius: BorderRadius["2"],
    borderBottomWidth: StyleSheet.hairlineWidth,
    overflow: "hidden",
  },
  accentBorder: {
    width: 3,
    alignSelf: "stretch",
    marginRight: Spacing["spacing-4"],
    borderRadius: 1,
  },
  leftContent: {
    flex: 1,
    flexDirection: "column",
    gap: Spacing["spacing-1"],
  },
  amountText: {
    fontWeight: "600",
  },
});
