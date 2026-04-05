import { Button } from "@/components/button";
import { ThemedText } from "@/components/themed-text";
import { BorderRadius, Spacing } from "@/constants/spacing";
import { useTheme } from "@/hooks/use-theme-color";
import { useSettingsStore } from "@/store/useSettingsStore";
import { showErrorToast } from "@/utils/toast";
import { useAssets } from "expo-asset";
import { Image } from "expo-image";
import { router } from "expo-router";
import { Platform, StyleSheet, View } from "react-native";

export default function HomeScreen() {
  const [assets] = useAssets([
    require("@/assets/images/plus.png"),
    require("@/assets/images/clock.png"),
    require("@/assets/images/gear.png"),
  ]);

  const Theme = useTheme();
  const { merchantId, isCustomerApiKeySet } = useSettingsStore();

  const handleStartPayment = () => {
    if (!merchantId || !isCustomerApiKeySet) {
      router.push("/settings");
      showErrorToast("Merchant information not configured");
      return;
    }
    router.push("/amount");
  };

  const handleActivityPress = () => router.push("/activity");
  const handleSettingsPress = () => router.push("/settings");

  return (
    <View style={styles.container}>
      {/* Primary CTA */}
      <Button
        onPress={handleStartPayment}
        style={[styles.primaryButton, { backgroundColor: Theme["bg-accent-primary"] }]}
      >
        <View style={[styles.primaryIconWrap, { backgroundColor: "rgba(0,0,0,0.1)" }]}>
          <Image
            source={assets?.[0]}
            style={styles.primaryIcon}
            tintColor="#202020"
            cachePolicy="memory-disk"
            priority="high"
          />
        </View>
        <ThemedText fontSize={22} style={styles.primaryLabel} color="text-invert">
          New Sale
        </ThemedText>
        <ThemedText fontSize={13} color="text-invert" style={styles.primarySub}>
          Start a new payment
        </ThemedText>
      </Button>

      {/* Secondary row */}
      <View style={styles.secondaryRow}>
        <Button
          onPress={handleActivityPress}
          style={[styles.secondaryButton, { backgroundColor: Theme["foreground-primary"], borderColor: Theme["border-primary"] }]}
        >
          <Image
            source={assets?.[1]}
            style={styles.secondaryIcon}
            tintColor={Theme["icon-default"]}
            cachePolicy="memory-disk"
          />
          <ThemedText fontSize={15} style={styles.secondaryLabel} color="text-primary">
            Activity
          </ThemedText>
        </Button>

        <Button
          onPress={handleSettingsPress}
          style={[styles.secondaryButton, { backgroundColor: Theme["foreground-primary"], borderColor: Theme["border-primary"] }]}
        >
          <Image
            source={assets?.[2]}
            style={styles.secondaryIcon}
            tintColor={Theme["icon-default"]}
            cachePolicy="memory-disk"
          />
          <ThemedText fontSize={15} style={styles.secondaryLabel} color="text-primary">
            Settings
          </ThemedText>
        </Button>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingHorizontal: Spacing["spacing-5"],
    paddingTop: Spacing["spacing-4"],
    paddingBottom: Platform.OS === "web" ? 0 : Spacing["spacing-7"],
    gap: Spacing["spacing-3"],
  },
  // Primary button
  primaryButton: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    borderRadius: BorderRadius["5"],
    gap: Spacing["spacing-2"],
  },
  primaryIconWrap: {
    width: 56,
    height: 56,
    borderRadius: BorderRadius["full"],
    alignItems: "center",
    justifyContent: "center",
    marginBottom: Spacing["spacing-2"],
  },
  primaryIcon: {
    width: 28,
    height: 28,
  },
  primaryLabel: {
    fontWeight: "700",
    letterSpacing: -0.3,
  },
  primarySub: {
    opacity: 0.75,
  },
  // Secondary row
  secondaryRow: {
    flexDirection: "row",
    gap: Spacing["spacing-3"],
    height: 120,
  },
  secondaryButton: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    borderRadius: BorderRadius["4"],
    borderWidth: StyleSheet.hairlineWidth,
    gap: Spacing["spacing-2"],
  },
  secondaryIcon: {
    width: 24,
    height: 24,
  },
  secondaryLabel: {
    fontWeight: "500",
  },
});
