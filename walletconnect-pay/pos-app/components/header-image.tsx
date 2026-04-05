import { Variants } from "@/constants/variants";
import { useSettingsStore } from "@/store/useSettingsStore";
import { Image } from "expo-image";
import { StyleSheet, Text, View } from "react-native";

interface HeaderImageProps {
  tintColor?: string;
  padding?: boolean;
}

export default function HeaderImage({ tintColor, padding }: HeaderImageProps) {
  const variant = useSettingsStore((state) => state.variant);
  const { brandLogo, brandLogoDark, brandLogoWidth } = Variants[variant];
  const resolvedTint = brandLogoDark ? undefined : tintColor;

  return (
    <View style={[styles.row, padding && styles.padding]}>
      <Image
        source={brandLogo}
        cachePolicy="memory-disk"
        priority="high"
        contentFit="contain"
        tintColor={resolvedTint}
        style={{ height: 32, width: brandLogoWidth ?? 185 }}
      />
      <Text style={[styles.payText, tintColor ? { color: tintColor } : undefined]}>
        Pay
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 5,
  },
  padding: {
    marginHorizontal: 8,
  },
  payText: {
    fontSize: 18,
    fontWeight: "600",
    color: "#202020",
  },
});
