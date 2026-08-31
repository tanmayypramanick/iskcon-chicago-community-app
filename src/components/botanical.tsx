import { memo } from "react";
import { Image, StyleSheet, View } from "react-native";

import tokens from "../../design-tokens.json";

const botanicalTile = require("../../assets/botanical-tile.png");

/**
 * A shared, pre-rendered botanical layer behind every screen.
 *
 * The original drew each petal, leaf and mandala as an individual native
 * view. Four mounted tabs meant hundreds of outlined views in Android's draw
 * traversal. This image is the same subtle marigold-and-peacock line art, but
 * Android can repeat one tiny cached bitmap instead. The two header washes
 * remain native circles so they scale cleanly on every phone ratio.
 */
export const BotanicalBackdrop = memo(function BotanicalBackdrop() {
  return (
    <View
      pointerEvents="none"
      style={styles.backdrop}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <Image
        source={botanicalTile}
        resizeMode="repeat"
        style={styles.tile}
        accessible={false}
        fadeDuration={0}
      />
      <View style={styles.sandalwoodWash} />
      <View style={styles.marigoldWash} />
    </View>
  );
});

const styles = StyleSheet.create({
  backdrop: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    overflow: "hidden",
  },
  sandalwoodWash: {
    position: "absolute",
    top: -190,
    left: -70,
    width: 380,
    height: 380,
    borderRadius: 190,
    backgroundColor: tokens.colors.sandalwood,
    opacity: 0.5,
  },
  marigoldWash: {
    position: "absolute",
    top: -140,
    right: -110,
    width: 300,
    height: 300,
    borderRadius: 150,
    backgroundColor: tokens.colors.marigoldSoft,
    opacity: 0.2,
  },
  tile: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
  },
});

/** A slim marigold-and-peacock rule that echoes a flower garland. */
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
