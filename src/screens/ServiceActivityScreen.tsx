import DateTimePicker, { type DateTimePickerEvent } from "@react-native-community/datetimepicker";
import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Alert, Platform, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, ListScreen, Screen, ScreenTitle } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { FormError, SevaCard } from "../features/services/components";
import { dateToKey, formatServiceDate } from "../features/services/format";
import {
  useDeleteServiceActivity,
  useDeleteServiceAssignmentActivity,
  useDeleteSevaRegistration,
  useServiceDashboard,
} from "../features/services/hooks";
import {
  buildCompletedSevaRows,
  shareCompletedSevaReport,
  type ReportRow,
} from "../features/services/report";
import type { ServicesStackParamList } from "../navigation/types";
import { DASHBOARD_HISTORY_DAYS } from "../features/services/api";
import { addChicagoDays } from "../lib/chicagoDate";
import { useNow } from "../lib/useNow";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "ServiceActivity">;

function FilterDate({ label, value, onChange, minimumDate }: { label: string; value: Date; onChange: (value: Date) => void; minimumDate?: Date }) {
  const [open, setOpen] = useState(false);
  const changed = (event: DateTimePickerEvent, selected?: Date) => {
    if (Platform.OS === "android") setOpen(false);
    if (event.type !== "dismissed" && selected) onChange(selected);
  };
  return (
    <View className="flex-1">
      <Text className="mb-1 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">{label}</Text>
      <Pressable className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-3" onPress={() => setOpen(true)}>
        <Ionicons name="calendar-outline" size={17} color={tokens.colors.indigo} />
        <Text className="ml-2 font-sans-bold text-sm text-stone">{dateToKey(value)}</Text>
      </Pressable>
      {open ? (
        <View className="mt-2 rounded-card border border-border bg-white p-2">
          <DateTimePicker value={value} minimumDate={minimumDate} mode="date" display={Platform.OS === "ios" ? "inline" : "default"} onChange={changed} />
          {Platform.OS === "ios" ? <Button onPress={() => setOpen(false)}>Done</Button> : null}
        </View>
      ) : null}
    </View>
  );
}

/**
 * The temple's hours record, on screen and in the spreadsheet.
 *
 * This is not a third list of completed seva. The two lists — "Recently
 * completed" on the tab and the searchable history behind its See all — are one
 * card per seva; this is one row per devotee per seva, which is what an hours
 * report is, and it is built from `buildCompletedSevaRows`: the same rows the
 * Excel export writes. They used to be two implementations of the same idea and
 * had already drifted, so the screen credited seva the file left out.
 */
export function ServiceActivityScreen(_: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const deleteSession = useDeleteServiceActivity();
  const deleteAssignment = useDeleteServiceAssignmentActivity();
  const removeRegistration = useDeleteSevaRegistration();
  const [search, setSearch] = useState("");
  const [fromDate, setFromDate] = useState(() => { const date = new Date(); date.setMonth(date.getMonth() - 3); return date; });
  const [toDate, setToDate] = useState(() => new Date());
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  // A seva finishing is what admits it to this list, so the clock has to tick.
  const now = useNow();
  const role = __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canDeleteAny = hasAccessPermission(role, "services.delete_any");
  const canExport = hasAccessPermission(role, "services.export_reports");
  const canOversee = hasAccessPermission(role, "services.oversee_activity");

  const items = useMemo(
    () => (dashboard.data ? buildCompletedSevaRows(dashboard.data, now) : []),
    [dashboard.data, now],
  );

  const filtered = items.filter((item) => {
    const term = search.trim().toLocaleLowerCase();
    const matches = !term || `${item.devotee} ${item.seva} ${item.location}`.toLocaleLowerCase().includes(term);
    return matches && item.date >= dateToKey(fromDate) && item.date <= dateToKey(toDate);
  });
  const error = dashboard.error ?? deleteSession.error ?? deleteAssignment.error;

  const remove = (item: ReportRow) => {
    Alert.alert("Remove completed seva?", "This permanently removes this activity record.", [
      { text: "Keep", style: "cancel" },
      {
        text: "Remove",
        style: "destructive",
        onPress: () => {
          if (item.verificationId) {
            removeRegistration.mutate(item.verificationId);
          } else if (item.assignmentId) {
            deleteAssignment.mutate(item.assignmentId);
          }
        },
      },
    ]);
  };

  if (!canOversee) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons name="lock-closed-outline" size={30} color={tokens.colors.indigo} />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Seva oversight access required
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            Your own completed seva remains available in My seva and history.
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <ListScreen
      topInset={false}
      data={filtered}
      keyExtractor={(item) => item.key}
      header={
        <>
          <ScreenTitle eyebrow="One row per devotee, per seva">
            Completed seva report
          </ScreenTitle>
          {canExport ? (
            <Pressable
              className="mb-section min-h-touch flex-row items-center justify-center rounded-button bg-indigo px-4"
              disabled={!dashboard.data || exporting}
              onPress={async () => {
                if (!dashboard.data) return;
                setExportError(null); setExporting(true);
                try { await shareCompletedSevaReport(dashboard.data); }
                catch (caught) { setExportError(caught instanceof Error ? caught.message : "The report could not be shared."); }
                finally { setExporting(false); }
              }}
            >
              <Ionicons name="download-outline" size={20} color={tokens.colors.white} />
              <Text className="ml-2 font-sans-bold text-base text-white">{exporting ? "Preparing report…" : "Download Excel report"}</Text>
            </Pressable>
          ) : null}
          <TextInput
            className="min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
            value={search}
            onChangeText={setSearch}
            placeholder="Search devotee, seva, or location"
            placeholderTextColor={tokens.colors.stoneMuted}
          />
          <View className="my-3 flex-row gap-3">
            <FilterDate minimumDate={new Date(addChicagoDays(-DASHBOARD_HISTORY_DAYS))} label="From" value={fromDate} onChange={setFromDate} />
            <FilterDate label="To" value={toDate} onChange={setToDate} />
          </View>
          <Text className="mb-3 font-sans-bold text-sm text-peacock">{filtered.length} completed offering{filtered.length === 1 ? "" : "s"}</Text>
        </>
      }
      renderItem={(item) => {
        const canRemove = canDeleteAny || item.devoteeId === activeUserId;
        return (
          <View className="mb-3">
            {/* The same card as every other seva list. This screen used to draw
                its own, which is how it ended up saying different things. */}
            <SevaCard
              name={item.seva}
              weekly={item.weekly}
              when={`${formatServiceDate(item.date)} · ${item.start}`}
              minutes={Number(item.minutes)}
              people={[{ id: item.devoteeId, name: item.devotee }]}
              showPeople
              action={
                canRemove
                  ? {
                      label: "Remove",
                      accessibilityLabel: `Remove ${item.seva}`,
                      onPress: () => remove(item),
                    }
                  : undefined
              }
            />
            {/* Where and how it was evidenced. Outside the card on purpose: the
                card is one fixed height in every list and stays that way. */}
            <Text className="mt-1 px-card font-sans text-xs text-stoneMuted" numberOfLines={1}>
              {item.location} · {item.verification}
            </Text>
          </View>
        );
      }}
      empty={
        dashboard.isLoading ? null : (
          <View className="rounded-card border border-border bg-white p-card">
            <Text className="text-center font-sans text-base text-stoneMuted">No completed seva matches these filters.</Text>
          </View>
        )
      }
      footer={
        error || exportError ? (
          <FormError message={exportError ?? (error instanceof Error ? error.message : "Activity could not be updated.")} />
        ) : null
      }
    />
  );
}
