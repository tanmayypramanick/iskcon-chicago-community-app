import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import { Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import { useCreateSanga } from "../features/sanga/hooks";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import type { DevoteesStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<DevoteesStackParamList, "CreateSanga">;

/**
 * Anyone may start a sanga; the President decides whether the temple has one.
 * The wait is said plainly up front, because a devotee who is not told will
 * look for their sanga in the list and conclude the app lost it.
 */
export function CreateSangaScreen({ navigation }: Props) {
  const create = useCreateSanga();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const submit = () => {
    setFormError(null);
    const cleanName = name.trim();
    if (!cleanName) {
      setFormError("Please give the sanga a name.");
      return;
    }
    create.mutate(
      { name: cleanName, description: description.trim() || null },
      { onSuccess: () => navigation.goBack() },
    );
  };

  const error =
    formError ??
    errorMessage(create.error, "That sanga could not be started just yet.");

  return (
    <Screen>
      <ScreenTitle eyebrow="A circle of your own">Start a sanga</ScreenTitle>

      <View className="mb-section flex-row items-start rounded-card border border-marigold bg-white p-card">
        <Ionicons
          name="hourglass-outline"
          size={20}
          color={tokens.colors.marigold}
        />
        <Text className="ml-3 min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
          The temple President sees your sanga before anybody else does. It
          appears for the congregation once they have approved it, and you will
          run it from then on.
        </Text>
      </View>

      {error ? <FormError message={error} /> : null}

      <SectionHeader title="Name" />
      <View className="mb-section min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="py-3 font-sans text-base text-stone"
          accessibilityLabel="Sanga name"
          autoCapitalize="words"
          autoCorrect={false}
          maxLength={80}
          placeholder="Youth sanga, Gita study, kirtan…"
          placeholderTextColor={tokens.colors.stoneMuted}
          returnKeyType="next"
          value={name}
          onChangeText={setName}
        />
      </View>

      <SectionHeader
        title="What it is for"
        subtitle="Optional, and it helps a devotee decide whether to ask to join."
      />
      <View className="mb-section min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="min-h-[96px] py-3 font-sans text-base leading-6 text-stone"
          accessibilityLabel="What this sanga is for"
          maxLength={400}
          multiline
          placeholder="Who it is for, when you meet, what you do together."
          placeholderTextColor={tokens.colors.stoneMuted}
          textAlignVertical="top"
          value={description}
          onChangeText={setDescription}
        />
      </View>

      <Button
        icon="people-outline"
        disabled={create.isPending}
        onPress={submit}
      >
        {create.isPending ? "Sending…" : "Send for approval"}
      </Button>
    </Screen>
  );
}
