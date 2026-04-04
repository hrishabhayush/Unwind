import { BorderRadius, Spacing } from "@/constants/spacing";
import { useTheme } from "@/hooks/use-theme-color";
import { formatDateTime } from "@/utils/misc";
import { formatFiatAmount } from "@/utils/currency";
import { formatTokenAmount } from "@/utils/tokens";
import { PaymentRecord } from "@/utils/types";
import { memo, useEffect } from "react";
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from "react-native-reanimated";
import { Button } from "./button";
import { FramedModal } from "./framed-modal";
import { StatusBadge } from "./status-badge";
import { ThemedText } from "./themed-text";
import { Image } from "expo-image";
import * as Clipboard from "expo-clipboard";
import { showSuccessToast } from "@/utils/toast";
import { toastConfig } from "@/utils/toasts";
import Toast from "react-native-toast-message";

const ANIMATION_DURATION = 200;
const EASING = Easing.inOut(Easing.ease);

interface TransactionDetailModalProps {
  visible: boolean;
  payment: PaymentRecord | null;
  onClose: () => void;
  onRefund?: (paymentId: string) => void;
  isRefunding?: boolean;
}

function truncateHash(hash?: string): string {
  if (!hash) return "-";
  if (hash.length <= 12) return hash;
  return `${hash.slice(0, 4)}...${hash.slice(-4)}`;
}

function getTokenIcon(symbol?: string): number | null {
  if (!symbol) return null;
  if (symbol === "USDC") return require("@/assets/images/tokens/usdc.png");
  if (symbol === "USDT") return require("@/assets/images/tokens/usdt.png");
  return null;
}

interface DetailRowProps {
  label: string;
  value?: string;
  children?: React.ReactNode;
  onPress?: () => void;
  copyable?: boolean;
  isFirst?: boolean;
  isLast?: boolean;
}

function DetailRow({
  label,
  value,
  children,
  onPress,
  copyable,
  isFirst,
  isLast,
}: DetailRowProps) {
  const theme = useTheme();

  const content = (
    <View
      style={[
        styles.detailRow,
        isFirst && styles.detailRowFirst,
        isLast && styles.detailRowLast,
        !isLast && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme["border-primary"] },
      ]}
    >
      <ThemedText fontSize={14} color="text-secondary" style={styles.labelText}>
        {label}
      </ThemedText>
      <View style={styles.valueContainer}>
        {children || (
          <ThemedText
            fontSize={15}
            color={copyable ? "text-primary" : "text-primary"}
            numberOfLines={1}
            ellipsizeMode="middle"
            style={styles.valueText}
          >
            {value}
          </ThemedText>
        )}
        {copyable && (
          <ThemedText
            fontSize={13}
            style={[styles.copyLabel, { color: theme["icon-accent-primary"] }]}
          >
            Copy
          </ThemedText>
        )}
      </View>
    </View>
  );

  if (onPress) return <Button onPress={onPress}>{content}</Button>;
  return content;
}

function TransactionDetailModalBase({
  visible,
  payment,
  onClose,
  onRefund,
  isRefunding = false,
}: TransactionDetailModalProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();

  const translateY = useSharedValue(Platform.OS === "web" ? 300 : 0);
  const refundFill = useSharedValue(0);
  const refundFillStyle = useAnimatedStyle(() => ({
    backgroundColor: `rgba(223, 74, 52, ${refundFill.value * 0.12})`,
  }));

  useEffect(() => {
    if (Platform.OS !== "web") return;
    if (visible) {
      translateY.value = withTiming(0, { duration: ANIMATION_DURATION, easing: EASING });
    } else {
      translateY.value = withTiming(300, { duration: ANIMATION_DURATION, easing: EASING });
    }
  }, [visible, translateY]);

  const sheetAnimatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  if (!payment) return null;

  const handleCopyPaymentId = async () => {
    if (!payment?.paymentId) return;
    await Clipboard.setStringAsync(payment.paymentId);
    showSuccessToast("Payment ID copied to clipboard");
  };

  const handleCopyHash = async () => {
    if (!payment?.transaction?.hash) return;
    await Clipboard.setStringAsync(payment.transaction.hash);
    showSuccessToast("Transaction hash copied to clipboard");
  };

  const hasCryptoRow = !!payment.tokenAmount;
  const hasHashRow = !!payment.transaction?.hash;

  // Total number of rows to compute isLast
  const rowCount = 3 + (hasCryptoRow ? 1 : 0) + 1 + (hasHashRow ? 1 : 0);
  let rowIndex = 0;

  const tokenIcon = hasCryptoRow
    ? getTokenIcon(payment.tokenAmount?.display.assetSymbol)
    : null;

  return (
    <FramedModal visible={visible} onRequestClose={onClose}>
      <View style={styles.overlay}>
        <Pressable style={StyleSheet.absoluteFill} onPress={onClose} />
        <Animated.View
          style={[
            styles.container,
            { backgroundColor: theme["bg-primary"] },
            sheetAnimatedStyle,
          ]}
        >
          <View
            style={[
              styles.containerInner,
              { paddingBottom: Math.max(insets.bottom, Spacing["spacing-6"]) },
            ]}
          >
            {/* Drag handle */}
            <View style={styles.dragHandleRow}>
              <View
                style={[
                  styles.dragHandle,
                  { backgroundColor: theme["border-secondary"] },
                ]}
              />
            </View>

            {/* Header */}
            <View style={styles.header}>
              <ThemedText
                fontSize={18}
                color="text-primary"
                style={styles.headerTitle}
              >
                Transaction Details
              </ThemedText>
              <Button
                onPress={onClose}
                style={[
                  styles.closeButton,
                  { borderColor: theme["border-secondary"] },
                ]}
              >
                <Image
                  style={styles.closeIcon}
                  tintColor={theme["icon-invert"]}
                  source={require("@/assets/images/close.png")}
                />
              </Button>
            </View>

            {/* Hero amount block */}
            <View style={styles.heroBlock}>
              <ThemedText fontSize={32} color="text-primary" style={styles.heroAmount}>
                {formatFiatAmount(payment.fiatAmount ? parseInt(payment.fiatAmount.value) : undefined, payment.fiatAmount?.unit)}
              </ThemedText>
              {hasCryptoRow && payment.tokenAmount && (
                <View style={styles.heroSubRow}>
                  <ThemedText fontSize={16} color="text-secondary">
                    {`${formatTokenAmount(
                      payment.tokenAmount.value,
                      payment.tokenAmount.display.decimals
                    )} ${payment.tokenAmount.display.assetSymbol}`}
                  </ThemedText>
                  {tokenIcon && (
                    <Image style={styles.tokenIcon} source={tokenIcon} />
                  )}
                </View>
              )}
            </View>

            <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
              {/* Detail list */}
              <View
                style={[
                  styles.detailList,
                  {
                    backgroundColor: theme["foreground-primary"],
                    borderColor: theme["border-primary"],
                  },
                ]}
              >
                <DetailRow
                  label="Date"
                  value={formatDateTime(payment.createdAt)}
                  isFirst={rowIndex++ === 0}
                  isLast={rowIndex === rowCount}
                />

                <DetailRow
                  label="Status"
                  isFirst={rowIndex++ === 0}
                  isLast={rowIndex === rowCount}
                >
                  <StatusBadge status={payment.status} />
                </DetailRow>

                <DetailRow
                  label="Amount"
                  value={formatFiatAmount(payment.fiatAmount ? parseInt(payment.fiatAmount.value) : undefined, payment.fiatAmount?.unit)}
                  isFirst={rowIndex++ === 0}
                  isLast={rowIndex === rowCount}
                />

                {hasCryptoRow && payment.tokenAmount && (
                  <DetailRow
                    label="Crypto received"
                    isFirst={rowIndex++ === 0}
                    isLast={rowIndex === rowCount}
                  >
                    <View style={styles.cryptoValue}>
                      <ThemedText fontSize={15} color="text-primary">
                        {`${formatTokenAmount(
                          payment.tokenAmount.value,
                          payment.tokenAmount.display.decimals
                        )} ${payment.tokenAmount.display.assetSymbol}`}
                      </ThemedText>
                      {tokenIcon && (
                        <Image style={styles.tokenIcon} source={tokenIcon} />
                      )}
                    </View>
                  </DetailRow>
                )}

                <DetailRow
                  label="Payment ID"
                  value={payment.paymentId}
                  onPress={handleCopyPaymentId}
                  copyable
                  isFirst={rowIndex++ === 0}
                  isLast={rowIndex === rowCount}
                />

                {hasHashRow && (
                  <DetailRow
                    label="Hash ID"
                    value={truncateHash(payment.transaction?.hash)}
                    onPress={handleCopyHash}
                    copyable
                    isFirst={rowIndex++ === 0}
                    isLast={rowIndex === rowCount}
                  />
                )}
              </View>
            </ScrollView>

            {payment.status === "succeeded" && onRefund && (
              <Pressable
                onPress={() => onRefund(payment.paymentId)}
                onPressIn={() => {
                  refundFill.value = withTiming(1, { duration: 80 });
                }}
                onPressOut={() => {
                  refundFill.value = withTiming(0, { duration: 150 });
                }}
                disabled={isRefunding}
                style={isRefunding && styles.refundButtonDisabled}
              >
                <Animated.View
                  style={[
                    styles.refundButton,
                    { borderColor: theme["icon-error"] },
                    refundFillStyle,
                  ]}
                >
                  <ThemedText
                    fontSize={15}
                    style={[
                      styles.refundButtonText,
                      { color: theme["icon-error"] },
                    ]}
                  >
                    {isRefunding ? "Processing refund…" : "Refund"}
                  </ThemedText>
                </Animated.View>
              </Pressable>
            )}
          </View>
        </Animated.View>
      </View>
      <Toast
        config={toastConfig}
        position="bottom"
        bottomOffset={insets.bottom}
        visibilityTime={2000}
      />
    </FramedModal>
  );
}

export const TransactionDetailModal = memo(TransactionDetailModalBase);

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.75)",
    justifyContent: "flex-end",
  },
  container: {
    borderTopLeftRadius: BorderRadius["5"],
    borderTopRightRadius: BorderRadius["5"],
    maxHeight: "85%",
  },
  containerInner: {
    paddingTop: Spacing["spacing-3"],
    paddingBottom: Spacing["spacing-6"],
    paddingHorizontal: Spacing["spacing-5"],
  },

  // Drag handle
  dragHandleRow: {
    alignItems: "center",
    marginBottom: Spacing["spacing-4"],
  },
  dragHandle: {
    width: 40,
    height: 4,
    borderRadius: BorderRadius["full"],
    opacity: 0.5,
  },

  // Header
  header: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: Spacing["spacing-6"],
  },
  headerTitle: {
    fontWeight: "600",
  },
  closeButton: {
    borderRadius: BorderRadius["3"],
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: "center",
    justifyContent: "center",
    padding: Spacing["spacing-3"],
  },
  closeIcon: {
    width: 20,
    height: 20,
  },

  // Hero amount
  heroBlock: {
    alignItems: "center",
    paddingVertical: Spacing["spacing-6"],
    marginBottom: Spacing["spacing-5"],
  },
  heroAmount: {
    fontWeight: "700",
    letterSpacing: -0.5,
    marginBottom: Spacing["spacing-2"],
  },
  heroSubRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: Spacing["spacing-2"],
  },

  // Detail list
  content: {
    flexGrow: 0,
  },
  detailList: {
    borderRadius: BorderRadius["3"],
    borderWidth: StyleSheet.hairlineWidth,
    overflow: "hidden",
  },
  detailRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingVertical: Spacing["spacing-4"],
    paddingHorizontal: Spacing["spacing-5"],
    minHeight: 52,
  },
  detailRowFirst: {
    // reserved for future top-specific overrides
  },
  detailRowLast: {
    borderBottomWidth: 0,
  },
  labelText: {
    flex: 0,
    marginRight: Spacing["spacing-4"],
  },
  valueContainer: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "flex-end",
    gap: Spacing["spacing-2"],
  },
  valueText: {
    textAlign: "right",
    flexShrink: 1,
  },
  copyLabel: {
    fontWeight: "500",
    flexShrink: 0,
  },

  // Refund button
  refundButton: {
    marginTop: Spacing["spacing-5"],
    borderRadius: BorderRadius["3"],
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: Spacing["spacing-4"],
  },
  refundButtonDisabled: {
    opacity: 0.5,
  },
  refundButtonText: {
    fontWeight: "600",
  },

  // Crypto inline display (used inside detail row children)
  cryptoValue: {
    flexDirection: "row",
    alignItems: "center",
    gap: Spacing["spacing-2"],
  },
  tokenIcon: {
    width: 18,
    height: 18,
  },
});
