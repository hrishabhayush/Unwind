import { BorderRadius, Spacing } from "@/constants/spacing";
import { useTheme } from "@/hooks/use-theme-color";
import { TransactionFilterType } from "@/utils/types";
import { memo, useCallback, useRef } from "react";
import { LayoutChangeEvent, ScrollView, StyleSheet } from "react-native";
import { Button } from "./button";
import { ThemedText } from "./themed-text";

interface FilterTabsProps {
  selectedFilter: TransactionFilterType;
  onFilterChange: (filter: TransactionFilterType) => void;
}

interface FilterOption {
  key: TransactionFilterType;
  label: string;
}

const FILTER_OPTIONS: FilterOption[] = [
  { key: "all", label: "All" },
  { key: "failed", label: "Failed" },
  { key: "pending", label: "Pending" },
  { key: "completed", label: "Completed" },
];

function FilterTabsBase({ selectedFilter, onFilterChange }: FilterTabsProps) {
  const theme = useTheme();
  const scrollRef = useRef<ScrollView>(null);
  const tabLayouts = useRef<Record<string, { x: number; width: number }>>({});

  const handleTabLayout = useCallback(
    (key: string, event: LayoutChangeEvent) => {
      const { x, width } = event.nativeEvent.layout;
      tabLayouts.current[key] = { x, width };
    },
    [],
  );

  const handleTabPress = useCallback(
    (key: TransactionFilterType) => {
      const layout = tabLayouts.current[key];
      if (layout && scrollRef.current) {
        const padding = Spacing["spacing-5"];
        scrollRef.current.scrollTo({
          x: layout.x - padding,
          animated: true,
        });
      }
      onFilterChange(key);
    },
    [onFilterChange],
  );

  return (
    <ScrollView
      ref={scrollRef}
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.scrollContent}
    >
      {FILTER_OPTIONS.map((option) => {
        const isSelected = selectedFilter === option.key;

        return (
          <Button
            key={option.key}
            onPress={() => handleTabPress(option.key)}
            onLayout={(e) => handleTabLayout(option.key, e)}
            style={[
              styles.tab,
              {
                backgroundColor: isSelected ? "#FFFFFF" : "transparent",
              },
            ]}
          >
            <ThemedText
              fontSize={13}
              fontWeight={isSelected ? "600" : "400"}
              color={isSelected ? "text-invert" : "text-secondary"}
            >
              {option.label}
            </ThemedText>
          </Button>
        );
      })}
    </ScrollView>
  );
}

export const FilterTabs = memo(FilterTabsBase);

const styles = StyleSheet.create({
  scrollContent: {
    gap: Spacing["spacing-1"],
    paddingVertical: Spacing["spacing-1"],
    paddingHorizontal: Spacing["spacing-5"],
  },
  tab: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: Spacing["spacing-2"],
    paddingHorizontal: Spacing["spacing-4"],
    borderRadius: BorderRadius["full"],
  },
});
