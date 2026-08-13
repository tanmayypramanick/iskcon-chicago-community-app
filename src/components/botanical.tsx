import { memo } from "react";
import { View, type ViewStyle } from "react-native";

import tokens from "../../design-tokens.json";

/**
 * Decorative temple motifs drawn with plain views — no SVG or gradient native
 * module, so this layer hot-reloads without a rebuild and costs nothing at
 * runtime beyond a handful of static, non-re-rendering views.
 *
 * Everything here is purely ornamental: it is always pointer-transparent and
 * hidden from screen readers.
 */

type Motif = {
  /** Distance from the top of the screen, as a fraction of screen height. */
  top: string;
  /** Negative values let a motif bleed off the edge, which reads as intentional. */
  left?: number;
  right?: number;
  size: number;
  rotate: number;
  opacity: number;
  color: string;
  kind: "lotus" | "mandala" | "leafSpray" | "petalPair";
};

/** A single teardrop petal: rounded on three corners, pointed at the fourth. */
function Petal({
  length,
  width,
  color,
  style,
}: {
  length: number;
  width: number;
  color: string;
  style?: ViewStyle;
}) {
  return (
    <View
      style={[
        {
          position: "absolute",
          width,
          height: length,
          borderColor: color,
          borderWidth: Math.max(1, Math.round(width * 0.09)),
          borderTopLeftRadius: width,
          borderTopRightRadius: width,
          borderBottomLeftRadius: width,
          borderBottomRightRadius: 2,
        },
        style,
      ]}
    />
  );
}

/** Eight petals radiating from a shared centre, with a seed ring inside. */
function Lotus({ size, color }: { size: number; color: string }) {
  const petalLength = size * 0.42;
  const petalWidth = size * 0.2;
  const petals = Array.from({ length: 8 }, (_, index) => index);

  return (
    <View style={{ width: size, height: size }}>
      {petals.map((index) => (
        <Petal
          key={index}
          length={petalLength}
          width={petalWidth}
          color={color}
          style={{
            left: size / 2 - petalWidth / 2,
            top: size / 2 - petalLength,
            transformOrigin: `${petalWidth / 2}px ${petalLength}px`,
            transform: [{ rotate: `${index * 45 + 22.5}deg` }],
          }}
        />
      ))}
      <View
        style={{
          position: "absolute",
          left: size / 2 - size * 0.09,
          top: size / 2 - size * 0.09,
          width: size * 0.18,
          height: size * 0.18,
          borderRadius: size * 0.09,
          borderWidth: Math.max(1, size * 0.016),
          borderColor: color,
        }}
      />
    </View>
  );
}

/** Concentric rings with a ring of dots — a simplified rangoli/mandala. */
function Mandala({ size, color }: { size: number; color: string }) {
  const dots = Array.from({ length: 12 }, (_, index) => index);
  const dotSize = size * 0.055;

  return (
    <View style={{ width: size, height: size }}>
      {[1, 0.72, 0.44].map((scale) => (
        <View
          key={scale}
          style={{
            position: "absolute",
            left: (size * (1 - scale)) / 2,
            top: (size * (1 - scale)) / 2,
            width: size * scale,
            height: size * scale,
            borderRadius: (size * scale) / 2,
            borderWidth: Math.max(1, size * 0.012),
            borderColor: color,
          }}
        />
      ))}
      {dots.map((index) => (
        <View
          key={index}
          style={{
            position: "absolute",
            left: size / 2 - dotSize / 2,
            top: size / 2 - dotSize / 2,
            width: dotSize,
            height: dotSize,
            borderRadius: dotSize / 2,
            backgroundColor: color,
            transformOrigin: `${dotSize / 2}px ${dotSize / 2}px`,
            transform: [
              { rotate: `${index * 30}deg` },
              { translateY: -size * 0.43 },
            ],
          }}
        />
      ))}
    </View>
  );
}

/** A tulasi-like sprig: a stem with leaves stepping up either side. */
function LeafSpray({ size, color }: { size: number; color: string }) {
  const leaves = Array.from({ length: 5 }, (_, index) => index);
  const leafLength = size * 0.3;
  const leafWidth = size * 0.15;

  return (
    <View style={{ width: size, height: size }}>
      <View
        style={{
          position: "absolute",
          left: size / 2,
          top: size * 0.08,
          width: Math.max(1, size * 0.012),
          height: size * 0.84,
          backgroundColor: color,
          borderRadius: size,
        }}
      />
      {leaves.map((index) => {
        const offsetY = size * 0.14 + index * size * 0.16;
        const toLeft = index % 2 === 0;
        return (
          <Petal
            key={index}
            length={leafLength}
            width={leafWidth}
            color={color}
            style={{
              left: toLeft ? size / 2 - leafWidth : size / 2,
              top: offsetY,
              transformOrigin: toLeft
                ? `${leafWidth}px ${leafLength}px`
                : `0px ${leafLength}px`,
              transform: [{ rotate: toLeft ? "-125deg" : "125deg" }],
            }}
          />
        );
      })}
    </View>
  );
}

/** Two crossed petals — a lighter accent for tight corners. */
function PetalPair({ size, color }: { size: number; color: string }) {
  return (
    <View style={{ width: size, height: size }}>
      {[-24, 26].map((angle, index) => (
        <Petal
          key={angle}
          length={size * 0.78}
          width={size * 0.34}
          color={color}
          style={{
            left: size * (index === 0 ? 0.1 : 0.34),
            top: size * 0.12,
            transformOrigin: `${size * 0.17}px ${size * 0.78}px`,
            transform: [{ rotate: `${angle}deg` }],
          }}
        />
      ))}
    </View>
  );
}

const MOTIFS: Motif[] = [
  { kind: "lotus", top: "4%", right: -52, size: 168, rotate: -14, opacity: 0.085, color: tokens.colors.marigold },
  { kind: "leafSpray", top: "17%", left: -46, size: 150, rotate: 18, opacity: 0.075, color: tokens.colors.peacock },
  { kind: "mandala", top: "33%", right: -66, size: 196, rotate: 0, opacity: 0.055, color: tokens.colors.peacock },
  { kind: "petalPair", top: "47%", left: -30, size: 108, rotate: -22, opacity: 0.08, color: tokens.colors.marigold },
  { kind: "lotus", top: "60%", left: -54, size: 176, rotate: 24, opacity: 0.06, color: tokens.colors.peacock },
  { kind: "leafSpray", top: "73%", right: -42, size: 142, rotate: -20, opacity: 0.075, color: tokens.colors.marigold },
  { kind: "mandala", top: "88%", left: -60, size: 170, rotate: 0, opacity: 0.05, color: tokens.colors.marigold },
  { kind: "petalPair", top: "96%", right: -26, size: 104, rotate: 16, opacity: 0.07, color: tokens.colors.peacock },
];

function MotifShape({ motif }: { motif: Motif }) {
  const shared = { size: motif.size, color: motif.color };
  if (motif.kind === "lotus") return <Lotus {...shared} />;
  if (motif.kind === "mandala") return <Mandala {...shared} />;
  if (motif.kind === "leafSpray") return <LeafSpray {...shared} />;
  return <PetalPair {...shared} />;
}

/**
 * The full-screen ornamental layer sitting behind every screen's content.
 * Rendered once per screen and never re-rendered.
 */
export const BotanicalBackdrop = memo(function BotanicalBackdrop() {
  return (
    <View
      pointerEvents="none"
      style={{ position: "absolute", top: 0, right: 0, bottom: 0, left: 0, overflow: "hidden" }}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      {/* A warm sandalwood wash behind the header, softened by two stacked
          translucent discs so it reads as light rather than a hard shape. */}
      <View
        style={{
          position: "absolute",
          top: -190,
          left: -70,
          width: 380,
          height: 380,
          borderRadius: 190,
          backgroundColor: tokens.colors.sandalwood,
          opacity: 0.5,
        }}
      />
      <View
        style={{
          position: "absolute",
          top: -140,
          right: -110,
          width: 300,
          height: 300,
          borderRadius: 150,
          backgroundColor: tokens.colors.marigoldSoft,
          opacity: 0.2,
        }}
      />

      {MOTIFS.map((motif, index) => (
        <View
          key={index}
          style={{
            position: "absolute",
            top: motif.top as unknown as number,
            ...(motif.left === undefined ? {} : { left: motif.left }),
            ...(motif.right === undefined ? {} : { right: motif.right }),
            opacity: motif.opacity,
            transform: [{ rotate: `${motif.rotate}deg` }],
          }}
        >
          <MotifShape motif={motif} />
        </View>
      ))}
    </View>
  );
});

/**
 * A slim marigold-and-peacock rule used to close a section, echoing a strung
 * flower garland.
 */
export const GarlandRule = memo(function GarlandRule() {
  const beads = [
    tokens.colors.marigold,
    tokens.colors.marigoldSoft,
    tokens.colors.peacock,
    tokens.colors.marigoldSoft,
    tokens.colors.marigold,
  ];

  return (
    <View
      className="my-5 flex-row items-center"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View className="h-px flex-1 bg-border" />
      <View className="mx-3 flex-row items-center gap-1.5">
        {beads.map((color, index) => (
          <View
            key={index}
            style={{
              width: index === 2 ? 9 : 6,
              height: index === 2 ? 9 : 6,
              borderRadius: 999,
              backgroundColor: color,
            }}
          />
        ))}
      </View>
      <View className="h-px flex-1 bg-border" />
    </View>
  );
});
