import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Alert, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { Button } from "../../components/ui";
import { pickDocument } from "../../lib/documentPicker";
import { FormError } from "../services/components";
import { errorMessage } from "../services/format";
import { usePublishVaisnavaCalendar } from "./hooks";
import { parseVaisnavaIcs } from "./ics";
import type { ParsedVaisnavaCalendar } from "./types";

const OFFICIAL_SOURCE_URL =
  "https://www.vaisnavacalendar.info/calendar-file-downloads/ics-ical-calendar-files";

type PendingUpload = {
  fileName: string;
  sourceFileText: string;
  parsed: ParsedVaisnavaCalendar;
};

/**
 * Replacing a published calendar year, for the few who may.
 *
 * It lives here, holding its own state, because none of it is any of the
 * calendar screen's business: a devotee opening the app on an Ekādaśī should
 * not scroll past a file picker and two text inputs, and the screen should not
 * be carrying six pieces of leader state to render a day. Collapsed by
 * default for the same reason — the action is rare and consequential, and
 * being available is not the same as being on the screen.
 */
export function CalendarPublishPanel({
  publishedYears,
  onPublished,
}: {
  publishedYears: readonly number[];
  /** Move the calendar to the year that was just replaced. */
  onPublished: (year: number) => void;
}) {
  const publish = usePublishVaisnavaCalendar();
  const [open, setOpen] = useState(false);
  const [pendingUpload, setPendingUpload] = useState<PendingUpload | null>(null);
  const [sourceName, setSourceName] = useState("ISKCON GCal calendar");
  const [sourceUrl, setSourceUrl] = useState("");
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  const publishError =
    uploadError ??
    errorMessage(publish.error, "This calendar could not be published.");

  const pickCalendarFile = async () => {
    setUploadError(null);
    setSuccessMessage(null);
    try {
      // Guarded in src/lib/documentPicker: a dynamic import here is compiled
      // to a module-scope require, so an older binary crashed on startup
      // rather than when a leader tapped this.
      const picked = await pickDocument();
      if (!picked) return;
      const response = await fetch(picked.uri);
      const sourceFileText = await response.text();
      const parsed = parseVaisnavaIcs(sourceFileText);
      setPendingUpload({
        fileName: picked.name || `vaisnava-calendar-${parsed.year}.ics`,
        sourceFileText,
        parsed,
      });
    } catch (error) {
      setPendingUpload(null);
      setUploadError(
        error instanceof Error
          ? error.message
          : "This calendar file could not be read.",
      );
    }
  };

  const confirmPublish = () => {
    if (!pendingUpload) return;
    const { parsed } = pendingUpload;
    const replacing = publishedYears.includes(parsed.year);
    Alert.alert(
      replacing
        ? `Replace the ${parsed.year} calendar?`
        : `Publish the ${parsed.year} calendar?`,
      replacing
        ? `All ${parsed.year} dates will be replaced together with the ${parsed.events.length} reviewed entries in this file.`
        : `${parsed.events.length} Chicago calendar entries will become visible to every devotee.`,
      [
        { text: "Not yet", style: "cancel" },
        {
          text: replacing ? "Replace year" : "Publish year",
          onPress: () =>
            publish.mutate(
              {
                year: parsed.year,
                events: parsed.events,
                fileName: pendingUpload.fileName,
                sourceFileText: pendingUpload.sourceFileText,
                sourceName: sourceName.trim() || "ISKCON GCal calendar",
                sourceUrl: sourceUrl.trim() || null,
              },
              {
                onSuccess: () => {
                  setPendingUpload(null);
                  setSuccessMessage(`${parsed.year} Vaiṣṇava Calendar published.`);
                  onPublished(parsed.year);
                },
              },
            ),
        },
      ],
    );
  };

  return (
    <View className="mt-section">
      <Pressable
        className="min-h-touch flex-row items-center justify-between rounded-card border border-border bg-white px-card"
        accessibilityRole="button"
        accessibilityState={{ expanded: open }}
        accessibilityLabel="Publish or replace a calendar year"
        onPress={() => setOpen((wasOpen) => !wasOpen)}
      >
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-sm text-stone">
            Publish or replace a calendar year
          </Text>
          <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
            Community Heads, Tech Admins and the President, one reviewed ICS
            file at a time.
          </Text>
        </View>
        <Ionicons
          name={open ? "chevron-up" : "chevron-down"}
          size={18}
          color={tokens.colors.indigo}
        />
      </Pressable>

      {open ? (
        <View className="mt-3 rounded-card border border-border bg-white p-card">
          {publishError ? <FormError message={publishError} /> : null}
          {successMessage ? (
            <View className="mb-3 flex-row items-center rounded-button bg-peacockSoft px-4 py-3">
              <Ionicons
                name="checkmark-circle"
                size={20}
                color={tokens.colors.peacock}
              />
              <Text className="ml-2 flex-1 font-sans-bold text-sm text-peacock">
                {successMessage}
              </Text>
            </View>
          ) : null}

          <Button
            variant="secondary"
            icon="document-attach-outline"
            onPress={pickCalendarFile}
          >
            Choose yearly ICS file
          </Button>

          {pendingUpload ? (
            <View className="mt-4">
              <View className="rounded-button bg-indigoSoft px-4 py-3">
                <Text className="font-sans-bold text-base text-indigo">
                  {pendingUpload.parsed.year} ·{" "}
                  {pendingUpload.parsed.events.length} entries
                </Text>
                <Text
                  className="mt-1 font-sans text-xs text-stoneMuted"
                  numberOfLines={2}
                >
                  {pendingUpload.fileName}
                </Text>
                <Text className="mt-1 font-sans text-xs text-stoneMuted">
                  {
                    pendingUpload.parsed.events.filter((event) =>
                      ["ekadasi", "fasting"].includes(event.kind),
                    ).length
                  }{" "}
                  Ekādaśī or fasting entries ·{" "}
                  {
                    pendingUpload.parsed.events.filter(
                      (event) => event.kind === "parana",
                    ).length
                  }{" "}
                  parana windows
                </Text>
              </View>

              <Text className="mb-1 mt-4 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
                Calendar source
              </Text>
              <TextInput
                className="min-h-touch rounded-button border border-border bg-ivory px-4 font-sans text-base text-stone"
                accessibilityLabel="Calendar source name"
                value={sourceName}
                onChangeText={setSourceName}
                placeholder="ISKCON GCal calendar"
                placeholderTextColor={tokens.colors.stoneMuted}
              />

              <Text className="mb-1 mt-3 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
                Source link (optional)
              </Text>
              <TextInput
                className="min-h-touch rounded-button border border-border bg-ivory px-4 font-sans text-base text-stone"
                accessibilityLabel="Calendar source link"
                value={sourceUrl}
                onChangeText={setSourceUrl}
                placeholder={OFFICIAL_SOURCE_URL}
                placeholderTextColor={tokens.colors.stoneMuted}
                autoCapitalize="none"
                autoCorrect={false}
                keyboardType="url"
              />

              <View className="mt-4">
                <Button
                  icon="cloud-upload-outline"
                  disabled={publish.isPending}
                  onPress={confirmPublish}
                >
                  {publish.isPending
                    ? "Publishing calendar…"
                    : `Publish ${pendingUpload.parsed.year} calendar`}
                </Button>
              </View>
            </View>
          ) : (
            <Text className="mt-3 font-sans text-xs leading-4 text-stoneMuted">
              The app validates the year and every event before anything is
              replaced. Other years remain unchanged.
            </Text>
          )}
        </View>
      ) : null}
    </View>
  );
}
