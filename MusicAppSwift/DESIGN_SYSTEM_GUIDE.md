# Design System Quick Reference

## Usage Guide for DesignSystem.swift

### Spacing

```swift
// Use these instead of hardcoded numbers
.padding(DesignSystem.Spacing.xs)   // 8px  - tight spacing
.padding(DesignSystem.Spacing.sm)   // 12px - small gaps
.padding(DesignSystem.Spacing.md)   // 16px - default (most common)
.padding(DesignSystem.Spacing.lg)   // 24px - major section gaps
.padding(DesignSystem.Spacing.xl)   // 32px - large padding
.padding(DesignSystem.Spacing.xxl)  // 48px - extra large padding

// In VStack/HStack
VStack(spacing: DesignSystem.Spacing.md) { ... }
HStack(spacing: DesignSystem.Spacing.sm) { ... }
```

### Typography

```swift
// Use these instead of .font(.system(...))
.font(DesignSystem.Typography.largeTitle)  // 34pt bold
.font(DesignSystem.Typography.title)       // 28pt bold
.font(DesignSystem.Typography.title2)      // 22pt bold (section headers)
.font(DesignSystem.Typography.title3)      // 20pt semibold
.font(DesignSystem.Typography.headline)    // 17pt semibold
.font(DesignSystem.Typography.bodyMedium)  // 15pt medium (song titles)
.font(DesignSystem.Typography.body)        // 15pt regular
.font(DesignSystem.Typography.subheadline) // 13pt regular (artists)
.font(DesignSystem.Typography.caption)     // 12pt regular (time, counts)
```

### Colors

```swift
// Use these instead of .blue, .gray, .secondary
.foregroundColor(DesignSystem.Colors.primary)      // Blue accent
.foregroundColor(DesignSystem.Colors.accent)       // Blue (interactive)
.foregroundColor(DesignSystem.Colors.primaryText)  // Black (main text)
.foregroundColor(DesignSystem.Colors.secondaryText) // Gray 70%
.background(DesignSystem.Colors.background)        // White

// Example
Text(song.title)
    .font(DesignSystem.Typography.bodyMedium)
    .foregroundColor(DesignSystem.Colors.primaryText)
    
Text(song.artist)
    .font(DesignSystem.Typography.subheadline)
    .foregroundColor(DesignSystem.Colors.secondaryText)
```

### Heights

```swift
// Standard component heights
.frame(height: DesignSystem.Heights.songRow)      // 68px
.frame(height: DesignSystem.Heights.miniPlayer)   // 64px
.frame(height: DesignSystem.Heights.playlistRow)  // 68px
```

### Corner Radius

```swift
.cornerRadius(DesignSystem.CornerRadius.sm)   // 8px
.cornerRadius(DesignSystem.CornerRadius.md)   // 12px
.cornerRadius(DesignSystem.CornerRadius.lg)   // 16px
.cornerRadius(DesignSystem.CornerRadius.xl)   // 20px
.cornerRadius(DesignSystem.CornerRadius.xxl)  // 24px

// Or with RoundedRectangle
RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
```

### Shadows

```swift
// Use consistent shadow presets
.shadow(
    color: DesignSystem.Shadow.small.color,
    radius: DesignSystem.Shadow.small.radius,
    x: DesignSystem.Shadow.small.x,
    y: DesignSystem.Shadow.small.y
)

// Available: .small, .medium, .large
.shadow(
    color: DesignSystem.Shadow.large.color,
    radius: DesignSystem.Shadow.large.radius,
    x: DesignSystem.Shadow.large.x,
    y: DesignSystem.Shadow.large.y
)
```

### Animations

```swift
// Use consistent timing
.animation(.easeInOut(duration: DesignSystem.Animation.quick), value: isPressed)  // 0.2s
.animation(.easeInOut(duration: DesignSystem.Animation.normal), value: showView)  // 0.3s
.animation(.easeInOut(duration: DesignSystem.Animation.slow), value: expanded)    // 0.4s

// With withAnimation
withAnimation(.easeInOut(duration: DesignSystem.Animation.normal)) {
    // state changes
}
```

### View Modifiers

```swift
// Card style (shadow + background)
View()
    .cardStyle()

// Press animation (scale effect)
Button { }
    .pressAnimation()

// Standard background
View()
    .standardBackground()

// Gradient background
View()
    .gradientBackground()
```

---

## Common Patterns

### Song Row (68px)
```swift
HStack(spacing: DesignSystem.Spacing.sm) {
    ArtworkView(size: 48)
    
    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
        Text(song.title)
            .font(DesignSystem.Typography.bodyMedium)
        Text(song.artist)
            .font(DesignSystem.Typography.subheadline)
            .foregroundColor(DesignSystem.Colors.secondaryText)
    }
    
    Spacer()
    
    Menu { /* actions */ } label: {
        Image(systemName: "ellipsis")
    }
}
.padding(.horizontal, DesignSystem.Spacing.md)
.frame(height: DesignSystem.Heights.songRow)
```

### Section Header
```swift
Text("Section Title")
    .font(DesignSystem.Typography.title2)
    .padding(.horizontal, DesignSystem.Spacing.lg)
```

### Card with Shadow
```swift
VStack(spacing: DesignSystem.Spacing.sm) {
    // content
}
.padding(DesignSystem.Spacing.md)
.background(
    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
        .fill(Color.white)
        .shadow(
            color: DesignSystem.Shadow.medium.color,
            radius: DesignSystem.Shadow.medium.radius,
            x: DesignSystem.Shadow.medium.x,
            y: DesignSystem.Shadow.medium.y
        )
)
```

### Button with Animation
```swift
Button(action: {
    withAnimation(.easeInOut(duration: DesignSystem.Animation.quick)) {
        // action
    }
}) {
    Text("Button")
        .font(DesignSystem.Typography.bodyMedium)
}
.pressAnimation()
```

### Empty State
```swift
VStack(spacing: DesignSystem.Spacing.md) {
    Image(systemName: "icon")
        .font(.system(size: 60))
        .foregroundColor(DesignSystem.Colors.secondaryText)
    
    Text("Title")
        .font(DesignSystem.Typography.title3)
    
    Text("Description")
        .font(DesignSystem.Typography.body)
        .foregroundColor(DesignSystem.Colors.secondaryText)
}
.padding(DesignSystem.Spacing.xxl)
```

---

## Benefits

### Before
```swift
VStack(spacing: 16) {
    Text("Title")
        .font(.system(size: 22, weight: .bold))
    Text("Subtitle")
        .font(.system(size: 13))
        .foregroundColor(.gray)
}
.padding(.horizontal, 20)
```

### After
```swift
VStack(spacing: DesignSystem.Spacing.md) {
    Text("Title")
        .font(DesignSystem.Typography.title2)
    Text("Subtitle")
        .font(DesignSystem.Typography.subheadline)
        .foregroundColor(DesignSystem.Colors.secondaryText)
}
.padding(.horizontal, DesignSystem.Spacing.lg)
```

**Advantages:**
- ✅ Self-documenting (`.lg` = large, `.title2` = section header)
- ✅ Easy to change globally
- ✅ Consistent across all views
- ✅ Type-safe (no typos in numbers)
- ✅ Follows Apple HIG standards

---

## Migration Checklist

When adding new views:
- [ ] Use DesignSystem.Spacing for all padding/spacing
- [ ] Use DesignSystem.Typography for all text
- [ ] Use DesignSystem.Colors for all colors
- [ ] Use DesignSystem.Heights for standard components
- [ ] Use DesignSystem.CornerRadius for all corners
- [ ] Use DesignSystem.Shadow for all shadows
- [ ] Use DesignSystem.Animation for all animations
- [ ] Apply .cardStyle() or .pressAnimation() where appropriate

When updating old views:
- [ ] Replace hardcoded numbers with Spacing constants
- [ ] Replace .font(.system(...)) with Typography constants
- [ ] Replace .blue/.gray with Colors constants
- [ ] Standardize row heights to 68px
- [ ] Use consistent animation durations

---

## Tips

1. **Most Common:** Use `.md` spacing (16px) as default
2. **Section Gaps:** Use `.lg` spacing (24px) between major sections
3. **Song Rows:** Always 68px height with 48px artwork
4. **Typography:** `bodyMedium` for titles, `subheadline` for subtitles
5. **Colors:** `primaryText` for main, `secondaryText` for secondary
6. **Animations:** `quick` (0.2s) for buttons, `normal` (0.3s) for transitions

---

*Keep this guide handy when building new features!*
