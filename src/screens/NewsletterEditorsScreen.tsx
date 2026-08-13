import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import { Alert, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  useAppointNewsletterEditor,
  useMayManageNewsletter,
  useNewsletterEditors,
  useRevokeNewsletterEditor,
} from "../features/newsletter/hooks";
import type { NewsletterEditor } from "../features/newsletter/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServiceDashboard } from "../features/services/hooks";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { usePrototypeSession } from "../store/usePrototypeSession";

/** Enough names to choose from without turning the picker into a directory. */
const MAX_CANDIDATES = 8;

function dayLabel(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return null;
  return formatChicagoShortDate(at);
}

function EditorRow({
  editor,
  busy,
  onRevoke,
}: {
  editor: NewsletterEditor;
  busy: boolean;
  onRevoke: () => void;
}) {
  const appointed = dayLabel(editor.appointed_at);
  const by = editor.appointed_by_name?.trim();

  return (
    <View className="mt-3 flex-row items-center rounded-card border border-border bg-white p-card">
      <Avatar
        name={editor.devotee_name}
        photoUrl={editor.devotee_photo_url}
        size="small"
        tone="peacock"
      />
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
          {editor.devotee_name}
        </Text>
        <Text className="font-sans text-xs leading-5 text-stoneMuted">
          {[by ? `Appointed by ${by}` : "Appointed", appointed]
            .filter(Boolean)
            .join(" · ")}
        </Text>
      </View>
      {editor.can_revoke ? (
        <Pressable
          className="ml-2 h-11 w-11 shrink-0 items-center justify-center rounded-pill"
          accessibilityRole="button"
          accessibilityLabel={`Remove ${editor.devotee_name} as a newsletter editor`}
          accessibilityState={{ disabled: busy }}
          disabled={busy}
          onPress={onRevoke}
        >
          <Ionicons
            name="person-remove-outline"
            size={20}
            color={tokens.colors.vermilion}
          />
        </Pressable>
      ) : null}
    </View>
  );
}

/**
 * Who is allowed to put out the newsletter.
 *
 * The appointment is a grant rather than a rank — one row, given by the
 * President or the Tech Admin and taken back the same way — so the devotee
 * appointed here keeps whatever role they already had and gains nothing except
 * the newsletter. Editors can see the team; only the two office holders are
 * shown a way to change it, and `can_revoke` on each row is the server saying
 * so.
 */
export function NewsletterEditorsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  // Appointing, unlike everything else on the newsletter, genuinely is a rank:
  // the migration gates it on `app.view_all` and never on the appointment, so
  // an editor may not appoint another. This ladder is only the fallback for the
  // moment before the first editor exists and there is no row to ask.
  const canAppoint = hasAccessPermission(role, "app.view_all");

  const reachable = useServerReachable();
  const mayManage = useMayManageNewsletter(activeUserId);
  const editors = useNewsletterEditors(mayManage.data !== false);
  const rows = editors.data ?? [];
  // `can_revoke` is the server answering the very question the ladder above is
  // guessing at, so it wins wherever there is a row to ask.
  const showPicker = rows.some((editor) => editor.can_revoke) || canAppoint;
  // The directory the devotee picker everywhere else reads from.
  const dashboard = useServiceDashboard(activeUserId);
  const appoint = useAppointNewsletterEditor();
  const revoke = useRevokeNewsletterEditor();

  const [adding, setAdding] = useState(false);
  const [search, setSearch] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const failed = editors.isError && editors.data === undefined;

  const editorIds = useMemo(
    () => new Set(rows.map((editor) => editor.devotee_id)),
    [rows],
  );

  const candidates = useMemo(() => {
    if (!adding) return [];
    const term = search.trim().toLocaleLowerCase();
    return (dashboard.data?.devotees ?? [])
      .filter(
        (devotee) =>
          !editorIds.has(devotee.id) &&
          (!term || devotee.name.toLocaleLowerCase().includes(term)),
      )
      .slice(0, MAX_CANDIDATES);
  }, [adding, dashboard.data?.devotees, editorIds, search]);

  const add = (devotee: { id: string; name: string }) => {
    setActionError(null);
    appoint.mutate(devotee.id, {
      onSuccess: () => {
        setSearch("");
        setAdding(false);
      },
      onError: (caught) =>
        setActionError(
          errorMessage(caught, `${devotee.name} could not be appointed.`),
        ),
    });
  };

  const confirmRevoke = (editor: NewsletterEditor) => {
    setActionError(null);
    Alert.alert(
      `Remove ${editor.devotee_name}?`,
      "They will no longer be able to post the newsletter or read the story requests devotees send in. Nothing else about their account changes.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () =>
            revoke.mutate(editor.devotee_id, {
              onError: (caught) =>
                setActionError(
                  errorMessage(
                    caught,
                    `${editor.devotee_name} could not be removed.`,
                  ),
                ),
            }),
        },
      ],
    );
  };

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(editor) => editor.devotee_id}
      header={
        <>
          <ScreenTitle eyebrow="Newsletter">Editors</ScreenTitle>

          <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
            An editor may post an issue, take one down, and read, answer and
            remove the story requests devotees send in. It is a job rather than
            a rank — nothing else about their account changes, and removing them
            here takes it back the same instant.
          </Text>

          <SectionHeader
            title="The team"
            subtitle={
              rows.length
                ? `${rows.length} ${rows.length === 1 ? "editor" : "editors"}, besides the President and the Tech Admin`
                : undefined
            }
            action={showPicker ? (adding ? "Done" : "Appoint") : undefined}
            onAction={
              showPicker
                ? () => {
                    setAdding((open) => !open);
                    setSearch("");
                  }
                : undefined
            }
          />

          {adding ? (
            <View className="mb-3">
              <View className="mb-2 flex-row items-center rounded-button border border-border bg-white px-4">
                <Ionicons
                  name="search"
                  size={19}
                  color={tokens.colors.indigo}
                />
                <TextInput
                  className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
                  value={search}
                  onChangeText={setSearch}
                  placeholder="Search devotee by name"
                  placeholderTextColor={tokens.colors.stoneMuted}
                  autoCapitalize="words"
                  autoCorrect={false}
                  accessibilityLabel="Search the congregation by name"
                />
              </View>

              <View className="overflow-hidden rounded-card border border-border bg-white">
                {candidates.map((devotee, index) => (
                  <View
                    key={devotee.id}
                    className={`min-h-[70px] flex-row items-center px-card py-2.5 ${
                      index < candidates.length - 1
                        ? "border-b border-border"
                        : ""
                    }`}
                  >
                    <Avatar
                      name={devotee.name}
                      photoUrl={devotee.photo_url}
                      size="small"
                    />
                    <Text
                      className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone"
                      numberOfLines={2}
                    >
                      {devotee.name}
                    </Text>
                    <Pressable
                      className={`min-h-10 shrink-0 flex-row items-center justify-center rounded-pill bg-marigold px-4 ${
                        appoint.isPending ? "opacity-60" : ""
                      }`}
                      accessibilityRole="button"
                      accessibilityLabel={`Appoint ${devotee.name} a newsletter editor`}
                      accessibilityState={{ disabled: appoint.isPending }}
                      disabled={appoint.isPending}
                      onPress={() => add(devotee)}
                    >
                      <Ionicons
                        name="add"
                        size={16}
                        color={tokens.colors.stone}
                        style={{ marginRight: 4 }}
                      />
                      <Text className="font-sans-bold text-sm text-stone">
                        Appoint
                      </Text>
                    </Pressable>
                  </View>
                ))}
                {!candidates.length ? (
                  <Text className="px-card py-6 text-center font-sans text-base text-stoneMuted">
                    {dashboard.isLoading
                      ? "Loading the congregation…"
                      : search.trim()
                        ? "No devotee outside the team matches that name."
                        : "Everyone in the congregation is already an editor."}
                  </Text>
                ) : null}
              </View>

              {candidates.length === MAX_CANDIDATES ? (
                <Text className="mt-2 font-sans text-xs text-stoneMuted">
                  Showing the first {MAX_CANDIDATES}. Type a name to narrow it.
                </Text>
              ) : null}
            </View>
          ) : null}

          {actionError ? <FormError message={actionError} /> : null}
        </>
      }
      renderItem={(editor) => (
        <EditorRow
          editor={editor}
          busy={revoke.isPending}
          onRevoke={() => confirmRevoke(editor)}
        />
      )}
      empty={
        failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              editors.error,
              "The editors could not be loaded.",
            )}
            onRetry={() => void editors.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={editors.isLoading}
            loadingLabel="Loading the team…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name="people-outline"
                    size={26}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  Nobody appointed yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  {showPicker
                    ? "The President and the Tech Admin can already post. Appoint the devotee who actually puts the newsletter together."
                    : "Only the President and the Tech Admin can post the newsletter at the moment."}
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
