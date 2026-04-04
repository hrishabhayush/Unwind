---
name: ui-ux
description: UI/UX design intelligence for the WalletConnect Pay POS app. Use when building or improving React Native screens, components, or flows. Covers design patterns, accessibility, animation with Reanimated, Skia graphics, payment UX, and the dark-mode fintech aesthetic used throughout this app.
---

# UI/UX — POS App Design Guide

Comprehensive design guide tailored to the WalletConnect Pay POS application. React Native + Expo stack with Skia, Reanimated, and a dark fintech aesthetic.

## Stack Context

| Layer | Library |
|-------|---------|
| Navigation | expo-router (file-based) + react-navigation bottom-tabs |
| Animation | react-native-reanimated 4, react-native-worklets |
| Graphics | @shopify/react-native-skia |
| Gesture | react-native-gesture-handler |
| State | zustand + react-query |
| Styling | StyleSheet (no Tailwind — pure RN styles) |
| Safe area | react-native-safe-area-context |

---

## 1. Visual Language

### Color Palette

```
Background:    #0A0A0A  (near-black, primary surface)
Surface:       #141414  (cards, modals)
Surface-2:     #1E1E1E  (elevated elements)
Border:        #2A2A2A  (subtle dividers)
Primary:       #3396FF  (WalletConnect blue — CTAs, highlights)
Success:       #4CAF50
Error:         #FF5252
Warning:       #FFB300
Text-primary:  #FFFFFF
Text-secondary:#A0A0A0
Text-muted:    #606060
```

### Typography

- **Heading**: `fontWeight: '700'`, `fontSize: 28–36` — payment amounts, screen titles
- **Body**: `fontWeight: '400'`, `fontSize: 16` — `lineHeight: 24`
- **Caption**: `fontWeight: '400'`, `fontSize: 12`, `color: text-secondary`
- **Numeric/Amount**: Use monospace or tabular nums — `fontVariant: ['tabular-nums']`
- **Minimum body size**: 16px (never below 14px)

### Spacing System

```
xs:  4
sm:  8
md:  16
lg:  24
xl:  32
2xl: 48
```

---

## 2. Component Patterns

### Amounts & Numbers

- Large amounts: `fontSize: 48–64`, `fontWeight: '700'`, `fontVariant: ['tabular-nums']`
- Decimal separator smaller than integer part (use nested `Text` spans)
- Currency symbol: 60–70% of amount font size, vertically aligned top
- Animate value changes with Reanimated `useSharedValue` + `withSpring`

### Buttons

```tsx
// Primary CTA
{
  backgroundColor: '#3396FF',
  borderRadius: 12,
  paddingVertical: 16,
  paddingHorizontal: 24,
  minHeight: 56,        // accessibility: 44px min touch target
}

// Secondary / ghost
{
  borderWidth: 1,
  borderColor: '#2A2A2A',
  borderRadius: 12,
  backgroundColor: 'transparent',
}

// Destructive
{
  backgroundColor: '#FF525220',
  borderWidth: 1,
  borderColor: '#FF5252',
}
```

- Always disable during async operations (`disabled`, reduced opacity 0.5)
- Show activity indicator inside button when loading — do not change button size
- Haptic feedback on primary actions: `expo-haptics` (already available via expo)

### Cards

```tsx
{
  backgroundColor: '#141414',
  borderRadius: 16,
  padding: 16,
  borderWidth: 1,
  borderColor: '#2A2A2A',
}
```

- Elevated cards: add `shadowColor: '#000'`, `shadowOpacity: 0.4`, `shadowRadius: 12`
- No card should be wider than the viewport minus `2 * 16` horizontal padding

### Modals & Bottom Sheets

- Use `framed-modal` component (already in `/components`)
- Header: title centered, close button top-right (44×44 touch target)
- Max height: 90% of screen
- Always have a safe area bottom inset
- Backdrop: semi-transparent `rgba(0,0,0,0.7)` with blur if Skia available

### Status & Feedback

```tsx
// Success state
{ backgroundColor: '#4CAF5015', borderColor: '#4CAF50', borderWidth: 1 }

// Error state
{ backgroundColor: '#FF525215', borderColor: '#FF5252', borderWidth: 1 }

// Loading shimmer — use /components/shimmer.tsx
```

---

## 3. Payment-Specific UX

### Payment Request Flow

1. **Amount entry** — large numeric keyboard, instant visual feedback
2. **Confirmation** — show full breakdown before submitting (amount, currency, network fee estimate)
3. **QR display** — QR code centered, prominent, with copy-address fallback
4. **Polling state** — animated indicator (not a spinner — use Skia or Reanimated pulse)
5. **Success/Failure** — full-screen state change with animation, clear CTA to continue

### QR Code

- Minimum size: 240×240 (scannable from ~50cm)
- High-contrast: dark foreground on light background or invert with a white border
- Always show wallet address text below, truncated in the middle: `0x1234…5678`
- Copy-to-clipboard button adjacent (not overlapping)

### Transaction History

- Group by date (Today, Yesterday, `DD MMM`)
- Status badge inline (use `/components/status-badge.tsx`)
- Amount right-aligned, color-coded (success green, pending yellow)
- Pull-to-refresh — `RefreshControl` with `tintColor: '#3396FF'`
- Empty state — use `/components/empty-state.tsx`, never a blank screen

---

## 4. Animation Guidelines

### Reanimated Patterns

```tsx
// Page entry — slide up + fade
entering={SlideInDown.springify().damping(18)}

// List item stagger
entering={FadeInDown.delay(index * 50).duration(300)}

// Button press feedback
useAnimatedStyle(() => ({
  transform: [{ scale: withSpring(pressed.value ? 0.96 : 1) }],
}))

// Amount change
useAnimatedStyle(() => ({
  transform: [{ scale: withSpring(1, { damping: 12, stiffness: 180 }) }],
}))
```

### Timing

| Interaction | Duration |
|-------------|----------|
| Button press | 100ms |
| Modal open | 280ms spring |
| Screen transition | 350ms (expo-router default) |
| List items | 200–300ms staggered |
| Success/failure full-screen | 400ms |

### Reduced Motion

Always check `useReducedMotion()` from Reanimated — skip or minimize animations when true.

---

## 5. Accessibility

- **Touch targets**: 44×44px minimum for all interactive elements
- **Color contrast**: 4.5:1 for normal text, 3:1 for large text (>18px bold)
- **Don't use color alone** for status — always pair with icon or text label
- **Focus order**: logical top-to-bottom, left-to-right
- **Loading states**: announce to screen reader with `accessibilityLiveRegion="polite"`
- **Error messages**: adjacent to the field that caused the error, `accessibilityRole="alert"`

---

## 6. Layout & Responsive

### Screen Structure

```tsx
<SafeAreaView style={{ flex: 1, backgroundColor: '#0A0A0A' }}>
  {/* Header — fixed height ~56px */}
  {/* Scrollable content — flex: 1 */}
  {/* Footer CTA — fixed at bottom, above safe area */}
</SafeAreaView>
```

### Web (expo-router web target)

- Use `/components/desktop-frame-wrapper.web.tsx` for desktop layout
- Max content width: 480px centered (POS is mobile-first)
- Keyboard shortcuts for desktop: Enter to confirm, Escape to cancel

### Numeric Keyboard

- Use `/components/numeric-keyboard.tsx` — never the system keyboard for amount input
- Delete button: right side, always visible
- Decimal: single press only, disable if already present

---

## 7. Common Anti-Patterns to Avoid

| Anti-pattern | Fix |
|--------------|-----|
| Spinner on full screen for every load | Use skeleton shimmer for content, spinner only for actions |
| Alert.alert() for non-critical info | Use toast (`react-native-toast-message`) |
| Text truncation hiding critical payment info | Wrap or scroll — never hide amounts |
| Hardcoded colors instead of palette | Reference the palette constants |
| onPress without haptic/visual feedback | Add scale animation + haptic |
| Modal that doesn't handle keyboard overlap | Use `KeyboardAvoidingView` or `KeyboardAwareScrollView` |
| Empty catch block hiding payment errors | Always surface errors to the user |
| Different border radii across similar components | Use 12 (interactive) or 16 (cards) consistently |

---

## 8. Pre-Delivery Checklist

### Visual
- [ ] Colors match palette (no hardcoded one-offs)
- [ ] Touch targets ≥ 44×44px
- [ ] Text minimum 16px body, 12px caption
- [ ] Consistent border radii (12 interactive, 16 cards)

### Interaction
- [ ] Loading states on all async actions
- [ ] Error states handled and visible
- [ ] Success/failure states have clear next action
- [ ] Haptics on primary actions

### Payment-Specific
- [ ] Amounts never truncated or hidden
- [ ] QR code ≥ 240×240
- [ ] Address shown with middle truncation + copy button
- [ ] Transaction states: pending / confirmed / failed all handled

### Accessibility
- [ ] Contrast ≥ 4.5:1 on all text
- [ ] All icons have `accessibilityLabel`
- [ ] `reduceMotion` respected in animations

### Platform
- [ ] Safe area insets applied (top and bottom)
- [ ] Web layout uses desktop-frame-wrapper
- [ ] No horizontal overflow on any screen size
