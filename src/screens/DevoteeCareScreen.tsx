import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { useState } from "react";
import { Alert, Image, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  RemoteImage,
  ScreenTitle,
} from "../components/ui";
import {
  pickMessageImage,
  useCarePosts,
  useCreateCarePost,
  useDeleteCarePost,
} from "../features/care/hooks";
import type { CarePost, PickedMessageImage } from "../features/care/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type { MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { CarePostScreen, formatCareTime } from "./CarePostScreen";

/** A card on the board. Enough to decide whether you can help, and no more. */
function CarePostCard({
  post,
  onOpen,
  onRemove,
}: {
  post: CarePost;
  onOpen: () => void;
  onRemove: () => void;
}) {
  return (
    <View className="mt-3 rounded-card border border-border bg-white">
      <Pressable
        className="p-card"
        accessibilityRole="button"
        accessibilityLabel={`Open ${post.author_name}'s request: ${post.title}`}
        onPress={onOpen}
      >
        <View className="flex-row items-center">
          <Avatar
            name={post.author_name}
            photoUrl={post.author_photo_url}
            size="small"
            tone="marigold"
          />
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-sans-bold text-sm text-stone"
              numberOfLines={1}
            >
              {post.author_name}
            </Text>
            <Text className="font-sans text-xs text-stoneMuted">
              {formatCareTime(post.created_at)}
            </Text>
          </View>
          {post.image_url ? (
            <RemoteImage
              uri={post.image_url}
              style={{ width: 48, height: 48, borderRadius: 12 }}
              resizeMode="cover"
              accessibilityIgnoresInvertColors
            />
          ) : null}
        </View>

        <Text
          className="mt-3 font-display text-xl leading-7 text-stone"
          numberOfLines={2}
        >
          {post.title}
        </Text>
        <Text
          className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted"
          numberOfLines={2}
        >
          {post.body}
        </Text>

        <View className="mt-3 flex-row items-center">
          <Ionicons
            name="chatbubbles-outline"
            size={16}
            color={tokens.colors.peacock}
          />
          <Text className="ml-1.5 font-sans-bold text-xs text-peacock">
            {post.reply_count === 0
              ? "No replies yet"
              : `${post.reply_count} repl${post.reply_count === 1 ? "y" : "ies"}`}
          </Text>
          <Text className="ml-auto font-sans-bold text-xs text-indigo">
            Open →
          </Text>
        </View>
      </Pressable>

      {post.can_remove ? (
        <Pressable
          className="min-h-touch flex-row items-center justify-center border-t border-border px-card"
          accessibilityRole="button"
          accessibilityLabel={`Remove the request "${post.title}"`}
          onPress={onRemove}
        >
          <Ionicons
            name="trash-outline"
            size={17}
            color={tokens.colors.vermilion}
          />
          <Text className="ml-2 font-sans-bold text-sm text-vermilion">
            Remove
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/**
 * The care board: a devotee asks the congregation for help, anyone answers.
 *
 * A post's thread is a full-screen modal rather than a route. The board is the
 * only way into a thread, it owns which one is open, and nothing else in the
 * app needs to send a devotee to one.
 */
export function DevoteeCareScreen() {
  const navigation = useNavigation();
  const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();

  const posts = useCarePosts();
  const createPost = useCreateCarePost(activeUserId);
  const removePost = useDeleteCarePost();

  const [composing, setComposing] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [image, setImage] = useState<PickedMessageImage | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [boardError, setBoardError] = useState<string | null>(null);
  const [openPostId, setOpenPostId] = useState<string | null>(null);

  const rows = posts.data ?? [];
  const failed = posts.isError && posts.data === undefined;
  // Read from the list rather than held apart, so a removed or refreshed post
  // cannot leave the thread showing a copy that no longer exists.
  const openPost = rows.find((post) => post.id === openPostId) ?? null;

  const resetComposer = () => {
    setTitle("");
    setBody("");
    setImage(null);
    setFormError(null);
    setComposing(false);
  };

  const attachPhoto = (source: "library" | "camera") => {
    void (async () => {
      try {
        const picked = await pickMessageImage(source);
        if (picked) setImage(picked);
      } catch (caught) {
        setFormError(
          errorMessage(caught, "That photo could not be added.") ?? null,
        );
      }
    })();
  };

  const choosePhoto = () => {
    Alert.alert("Add a photo", undefined, [
      { text: "Take a photo", onPress: () => attachPhoto("camera") },
      { text: "Choose from library", onPress: () => attachPhoto("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const post = () => {
    setFormError(null);
    if (!title.trim()) {
      setFormError("Please give your request a title.");
      return;
    }
    if (!body.trim()) {
      setFormError("Please say what you need help with.");
      return;
    }
    createPost.mutate(
      { title: title.trim(), body: body.trim(), image },
      {
        onSuccess: resetComposer,
        onError: (caught) =>
          setFormError(
            errorMessage(caught, "That request could not be posted.") ?? null,
          ),
      },
    );
  };

  const confirmRemove = (target: CarePost) => {
    Alert.alert(
      "Remove this request?",
      `"${target.title}" and its replies will come off the board.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () => {
            if (openPostId === target.id) setOpenPostId(null);
            removePost.mutate(target.id, {
              onError: (caught) =>
                setBoardError(
                  errorMessage(caught, "That request could not be removed.") ??
                    null,
                ),
            });
          },
        },
      ],
    );
  };

  // The profile lives on the Devotees tab, so the thread has to come down
  // first — a modal left open would sit over the screen it just opened.
  const openDevotee = (devoteeId: string) => {
    setOpenPostId(null);
    tabs?.navigate("Devotees", {
      screen: "DevoteeProfile",
      params: { devoteeId },
    });
  };

  return (
    <>
      <ListScreen
        topInset={false}
        data={rows}
        keyExtractor={(item) => item.id}
        header={
          <>
            <ScreenTitle>Devotees helping devotees</ScreenTitle>

            {composing ? (
              <View className="rounded-card border border-border bg-white p-card">
                <Text className="font-sans-bold text-lg text-stone">
                  What do you need?
                </Text>
                <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                  The congregation sees this. Nobody is pinged — devotees will
                  find it here.
                </Text>

                <TextInput
                  className="mt-4 min-h-touch rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
                  value={title}
                  onChangeText={(value) => {
                    setTitle(value);
                    if (formError) setFormError(null);
                  }}
                  placeholder="A short title, e.g. “A lift to Sunday feast”"
                  placeholderTextColor={tokens.colors.stoneMuted}
                  accessibilityLabel="Title of your request"
                />

                <TextInput
                  className="mt-3 min-h-[112px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
                  value={body}
                  onChangeText={(value) => {
                    setBody(value);
                    if (formError) setFormError(null);
                  }}
                  placeholder="Say a little more, so a devotee knows how to help"
                  placeholderTextColor={tokens.colors.stoneMuted}
                  multiline
                  textAlignVertical="top"
                  accessibilityLabel="What you need help with"
                />

                {image ? (
                  <View className="mt-3 flex-row items-center rounded-button border border-border bg-ivory p-2">
                    <Image
                      source={{ uri: image.uri }}
                      style={{ width: 56, height: 56, borderRadius: 12 }}
                      resizeMode="cover"
                      accessibilityIgnoresInvertColors
                      accessibilityLabel="The photo you added"
                    />
                    <Text className="ml-3 min-w-0 flex-1 font-sans text-sm text-stoneMuted">
                      Photo added
                    </Text>
                    <Pressable
                      className="h-10 w-10 items-center justify-center rounded-pill"
                      accessibilityRole="button"
                      accessibilityLabel="Remove the photo"
                      onPress={() => setImage(null)}
                    >
                      <Ionicons
                        name="close"
                        size={20}
                        color={tokens.colors.vermilion}
                      />
                    </Pressable>
                  </View>
                ) : (
                  <View className="mt-3">
                    <Button
                      variant="secondary"
                      icon="image-outline"
                      onPress={choosePhoto}
                    >
                      Add a photo — optional
                    </Button>
                  </View>
                )}

                <View className="mt-3 gap-2">
                  <Button
                    icon="heart-outline"
                    disabled={createPost.isPending}
                    onPress={post}
                  >
                    {createPost.isPending ? "Posting…" : "Post my request"}
                  </Button>
                  <Button
                    variant="secondary"
                    disabled={createPost.isPending}
                    onPress={resetComposer}
                  >
                    Cancel
                  </Button>
                </View>

                {formError ? <FormError message={formError} /> : null}
              </View>
            ) : (
              <Button icon="add" onPress={() => setComposing(true)}>
                Ask for help
              </Button>
            )}

            {boardError ? <FormError message={boardError} /> : null}

            <Text className="mb-1 mt-section font-sans-bold text-lg text-stone">
              {rows.length ? "Devotees asking" : "The board"}
            </Text>
          </>
        }
        renderItem={(item) => (
          <CarePostCard
            post={item}
            onOpen={() => setOpenPostId(item.id)}
            onRemove={() => confirmRemove(item)}
          />
        )}
        empty={
          failed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                posts.error,
                "The care board could not be loaded.",
              )}
              onRetry={() => void posts.refetch()}
            />
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={posts.isLoading}
              loadingLabel="Loading the care board…"
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                    <Ionicons
                      name="heart-outline"
                      size={26}
                      color={tokens.colors.peacock}
                    />
                  </View>
                  <Text className="mt-4 text-center font-display text-xl text-stone">
                    Nobody has asked yet
                  </Text>
                  <Text className="mt-2 max-w-72 text-center font-sans text-sm leading-5 text-stoneMuted">
                    A lift to the temple, a spare tulsi plant, some association
                    in a hard week — ask, and the congregation will see it.
                  </Text>
                </View>
              }
            />
          )
        }
      />

      <CarePostScreen
        post={openPost}
        onClose={() => setOpenPostId(null)}
        onOpenDevotee={openDevotee}
      />
    </>
  );
}
