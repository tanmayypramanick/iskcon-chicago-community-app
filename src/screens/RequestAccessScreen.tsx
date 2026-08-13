import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  Button,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  useAccessApprovers,
  useCreateAccessRequest,
  useCurrentAccessProfile,
} from "../features/access/hooks";
import {
  accessPermissionSummaries,
  accessPermissionsGained,
  accessRoleLabels,
  getRequestableAccessRoles,
  grantableRoleSummaries,
  isAccessRole,
  permissionsByRole,
  type AccessRole,
  type GrantableAccessRole,
} from "../features/access/model";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import type { ProfileStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ProfileStackParamList, "RequestAccess">;

const minimumMessageLength = 10;

/** The database hands back a plain role name; only known ones have a label. */
function approverRoleLabel(roleName: string) {
  return isAccessRole(roleName) ? accessRoleLabels[roleName] : roleName;
}

function isGrantable(role: AccessRole): role is GrantableAccessRole {
  return role === "volunteer" || role === "core";
}

/**
 * One level, with what it would actually let this devotee do. The list is the
 * permissions the level adds to what they hold today rather than a written
 * description, so it cannot drift from what the access really grants.
 */
function LevelCard({
  role,
  currentRole,
  selected,
  onSelect,
}: {
  role: GrantableAccessRole;
  currentRole: AccessRole;
  selected: boolean;
  onSelect: () => void;
}) {
  const gained = accessPermissionsGained(currentRole, role);

  return (
    <Pressable
      className={`mb-3 rounded-card border bg-white p-card ${
        selected ? "border-marigold" : "border-border"
      }`}
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      accessibilityLabel={`Choose ${accessRoleLabels[role]} access`}
      onPress={onSelect}
    >
      <View className="flex-row items-start">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-lg text-stone">
            {accessRoleLabels[role]}
          </Text>
          <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
            {grantableRoleSummaries[role]}
          </Text>
        </View>
        <Ionicons
          name={selected ? "checkmark-circle" : "ellipse-outline"}
          size={24}
          color={selected ? tokens.colors.peacock : tokens.colors.stoneMuted}
        />
      </View>

      <View className="mt-3 rounded-button bg-marigoldSoft px-3 py-2.5">
        <Text className="font-sans-bold text-xs uppercase tracking-wider text-stone">
          What it lets you do that you cannot today
        </Text>
        <View className="mt-2 gap-2">
          {gained.map((permission) => (
            <View key={permission} className="flex-row items-start">
              <Ionicons
                name="checkmark-circle"
                size={17}
                color={tokens.colors.peacock}
              />
              <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
                {accessPermissionSummaries[permission]}
              </Text>
            </View>
          ))}
        </View>
      </View>
    </Pressable>
  );
}

/**
 * A devotee asking to be trusted with more. The levels are explained before
 * either is chosen, so the reason underneath is written knowingly rather than
 * about a word whose meaning the devotee had to guess.
 */
export function RequestAccessScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const createRequest = useCreateAccessRequest(activeUserId);
  const approvers = useAccessApprovers();

  const currentRole = profile.data?.role ?? "devotee";
  const offeredRoles = getRequestableAccessRoles(currentRole).filter(
    isGrantable,
  );

  const [chosenRole, setChosenRole] = useState<GrantableAccessRole | null>(
    route.params?.role ?? null,
  );
  const [message, setMessage] = useState("");
  const [approverId, setApproverId] = useState<string | null>(null);
  const [approverSearch, setApproverSearch] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (createRequest.isSuccess) navigation.goBack();
  }, [createRequest.isSuccess, navigation]);

  const approverCandidates = useMemo(() => {
    const query = approverSearch.trim().toLocaleLowerCase();
    return (approvers.data ?? []).filter(
      (person) => !query || person.name.toLocaleLowerCase().includes(query),
    );
  }, [approverSearch, approvers.data]);

  const trimmed = message.trim();
  const stillNeeded = minimumMessageLength - trimmed.length;
  // A level arriving in the route is only a starting point; the profile is the
  // authority on what this devotee may actually ask for.
  const selectedRole =
    chosenRole && offeredRoles.includes(chosenRole) ? chosenRole : null;

  if (!offeredRoles.length) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            {profile.isLoading
              ? "Loading your access…"
              : `Your ${accessRoleLabels[currentRole]} access already covers everything the app can grant.`}
          </Text>
        </View>
      </Screen>
    );
  }

  const submit = () => {
    setFormError(null);
    // Checked in reading order, so the error names the first thing missing.
    if (!selectedRole) {
      setFormError("Choose the access level you would like.");
      return;
    }
    if (!approverId) {
      setFormError("Choose who you are asking.");
      return;
    }
    if (trimmed.length < minimumMessageLength) {
      setFormError(
        "Please say a little more about why you would like this access — at least 10 characters.",
      );
      return;
    }
    createRequest.mutate({
      requestedRole: selectedRole,
      message: trimmed,
      approverId,
    });
  };

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Request access">
        {selectedRole ? accessRoleLabels[selectedRole] : "More ways to serve"}
      </ScreenTitle>

      <SectionHeader
        title="What each level means"
        subtitle="Everything you can do today stays as it is."
      />
      {offeredRoles.map((role) => (
        <LevelCard
          key={role}
          role={role}
          currentRole={currentRole}
          selected={role === selectedRole}
          onSelect={() => {
            setChosenRole(role);
            if (formError) setFormError(null);
          }}
        />
      ))}

      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
          Today · {accessRoleLabels[currentRole]}
        </Text>
        <View className="mt-2 gap-1.5">
          {permissionsByRole[currentRole].map((permission) => (
            <Text
              key={permission}
              className="font-sans text-sm leading-5 text-stoneMuted"
            >
              · {accessPermissionSummaries[permission]}
            </Text>
          ))}
        </View>
      </View>

      <SectionHeader
        title="Who are you asking?"
        subtitle="A Community Head, the President or a Tech Admin. They are told, and so are the President and Tech Admin."
      />
      <View className="mb-3 min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
        <Ionicons name="search" size={19} color={tokens.colors.stoneMuted} />
        <TextInput
          className="ml-3 min-w-0 flex-1 py-3 font-sans text-base text-stone"
          accessibilityLabel="Search devotees you can ask"
          placeholder="Search by name"
          placeholderTextColor={tokens.colors.stoneMuted}
          autoCapitalize="words"
          autoCorrect={false}
          value={approverSearch}
          onChangeText={setApproverSearch}
        />
      </View>

      {approverCandidates.length ? (
        <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
          {approverCandidates.map((person, index) => {
            const selected = person.id === approverId;
            return (
              <Pressable
                key={person.id}
                className={`min-h-touch flex-row items-center px-card py-3 ${
                  index < approverCandidates.length - 1
                    ? "border-b border-border"
                    : ""
                } ${selected ? "bg-marigoldSoft" : ""}`}
                accessibilityRole="radio"
                accessibilityState={{ selected }}
                accessibilityLabel={`Ask ${person.name}, ${approverRoleLabel(
                  person.role_name,
                )}`}
                onPress={() => {
                  setApproverId(person.id);
                  if (formError) setFormError(null);
                }}
              >
                <Avatar
                  name={person.name}
                  photoUrl={person.photo_url}
                  size="small"
                  tone="peacock"
                />
                <View className="ml-3 min-w-0 flex-1">
                  <Text
                    className="font-sans-bold text-base text-stone"
                    numberOfLines={1}
                  >
                    {person.name}
                  </Text>
                  <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                    {approverRoleLabel(person.role_name)}
                  </Text>
                </View>
                <Ionicons
                  name={selected ? "checkmark-circle" : "ellipse-outline"}
                  size={24}
                  color={
                    selected ? tokens.colors.peacock : tokens.colors.stoneMuted
                  }
                />
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View className="mb-section items-center rounded-card border border-border bg-white px-card py-7">
          <Text className="text-center font-sans text-sm leading-5 text-stoneMuted">
            {approvers.isLoading
              ? "Loading the devotees you can ask…"
              : approverSearch
                ? "No devotee matches that name."
                : "There is no Community Head, Tech Admin, or President to ask yet."}
          </Text>
        </View>
      )}

      <SectionHeader
        title="Why would you like this access?"
        subtitle="Whoever you asked reads this before deciding."
      />
      <TextInput
        className="min-h-[112px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
        value={message}
        onChangeText={(value) => {
          setMessage(value);
          if (formError) setFormError(null);
        }}
        placeholder="The seva you would like to help with, and why"
        placeholderTextColor={tokens.colors.stoneMuted}
        multiline
        textAlignVertical="top"
        accessibilityLabel="Why would you like this access?"
      />
      <Text className="mt-1.5 font-sans text-sm text-stoneMuted">
        {stillNeeded > 0
          ? `${stillNeeded} more character${stillNeeded === 1 ? "" : "s"} needed`
          : `${trimmed.length} characters — ready to send`}
      </Text>

      {formError || createRequest.error ? (
        <View className="mt-3">
          <FormError
            message={
              formError ??
              errorMessage(
                createRequest.error,
                "This request could not be sent.",
              ) ??
              "This request could not be sent."
            }
          />
        </View>
      ) : null}

      <View className="mt-section">
        <Button disabled={createRequest.isPending} onPress={submit}>
          {createRequest.isPending
            ? "Sending…"
            : selectedRole
              ? `Request ${accessRoleLabels[selectedRole]} access`
              : "Choose a level to continue"}
        </Button>
      </View>
    </Screen>
  );
}
