import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Device from "expo-device";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Linking,
  Modal,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, Button, Screen, SectionHeader } from "../components/ui";
import { dateToKey, errorMessage } from "../features/services/format";
import {
  CustomServiceInput,
  DateField,
  FormError,
  ServiceTypePicker,
  TimeField,
} from "../features/services/components";
import {
  useRequestSevaVerification,
  useServiceDashboard,
  useServiceQrTokens,
  useSevaVerifiers,
} from "../features/services/hooks";
import type { SevaVerifier } from "../features/services/types";
import {
  chicagoWallClockToInstant,
  getChicagoZoneAbbreviation,
  toDatabaseTime,
} from "../lib/chicagoDate";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "FindSeva">;

function roleLabel(roleName: string) {
  if (roleName === "president") return "President";
  if (roleName === "tech") return "Tech Admin";
  return "Community Head";
}

/**
 * Registering seva. The devotee identifies it by temple QR or from the
 * catalog, states the day and the Chicago times, and picks the member who will
 * verify it. Registration is never blocked by verification — the record exists
 * immediately and is placed by the clock; verification only confirms it.
 */
export function FindSevaScreen({ navigation, route }: Props) {
  const isFocused = useIsFocused();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const verifiers = useSevaVerifiers();
  const register = useRequestSevaVerification();

  const [permission, requestPermission] = useCameraPermissions();
  const [scanMode, setScanMode] = useState(Boolean(route.params?.scan));
  const [scanLocked, setScanLocked] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);

  const [qrToken, setQrToken] = useState<string | null>(null);
  const [serviceTypeId, setServiceTypeId] = useState<string | null>(null);
  const [customSelected, setCustomSelected] = useState(false);
  const [customName, setCustomName] = useState("");
  const [locationText, setLocationText] = useState("ISKCON Chicago Temple");
  const [day, setDay] = useState(() => new Date());
  const [startTime, setStartTime] = useState(() => new Date());
  const [endTime, setEndTime] = useState(() => {
    const value = new Date();
    value.setHours(value.getHours() + 1);
    return value;
  });
  const [verifierId, setVerifierId] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const isIosSimulator = Platform.OS === "ios" && !Device.isDevice;
  const qrTokens = useServiceQrTokens(scanMode && isIosSimulator);
  const zone = getChicagoZoneAbbreviation();

  const matchingVerifiers = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (verifiers.data ?? []).filter(
      (person) => !query || person.name.toLocaleLowerCase().includes(query),
    );
  }, [search, verifiers.data]);

  const selectedVerifier: SevaVerifier | undefined = (verifiers.data ?? []).find(
    (person) => person.id === verifierId,
  );

  const acceptScannedCode = useCallback(
    (rawData: string) => {
      if (scanLocked) return;
      setScanLocked(true);
      setFormError(null);
      const data = rawData.trim();
      if (!data) {
        setQrToken(null);
        setScanMode(false);
        setFormError("That is not an ISKCON Chicago seva QR code.");
        return;
      }
      setQrToken(data);
      setServiceTypeId(null);
      setCustomSelected(false);
      setScanMode(false);
    },
    [scanLocked],
  );

  useEffect(() => {
    if (!isFocused) setScanMode(false);
  }, [isFocused]);

  const submit = () => {
    setFormError(null);
    if (!qrToken && !serviceTypeId && (!customSelected || customName.trim().length < 2)) {
      setFormError("Scan the temple QR, choose a seva, or type the seva you will do.");
      return;
    }
    if (!verifierId) {
      setFormError("Choose the member who will verify this seva.");
      return;
    }

    // The chosen day and times are read as Chicago wall-clock, whatever zone
    // the phone happens to be set to.
    const dayKey = dateToKey(day);
    const startAt = chicagoWallClockToInstant(dayKey, toDatabaseTime(startTime));
    let endAt = chicagoWallClockToInstant(dayKey, toDatabaseTime(endTime));
    if (endAt <= startAt) {
      // An end earlier than the start means the seva runs past midnight.
      const [year, month, dayOfMonth] = dayKey.split("-").map(Number);
      const nextDayKey = new Date(Date.UTC(year, month - 1, dayOfMonth + 1))
        .toISOString()
        .slice(0, 10);
      endAt = chicagoWallClockToInstant(nextDayKey, toDatabaseTime(endTime));
    }
    if (endAt.getTime() - startAt.getTime() > 12 * 60 * 60 * 1000) {
      setFormError("The end time must be within 12 hours of the start.");
      return;
    }
    if (endAt.getTime() <= Date.now()) {
      setFormError(
        "That seva has already finished. Register seva for now or for a time ahead.",
      );
      return;
    }

    register.mutate(
      {
        serviceTypeId: qrToken || customSelected ? null : serviceTypeId,
        customName: qrToken || !customSelected ? null : customName.trim(),
        qrToken,
        startAt: startAt.toISOString(),
        endAt: endAt.toISOString(),
        locationText: locationText.trim() || "ISKCON Chicago Temple",
        verifierId,
      },
      { onSuccess: () => navigation.goBack() },
    );
  };

  const error =
    formError ??
    errorMessage(register.error, "This seva could not be registered.") ??
    errorMessage(dashboard.error, "Seva could not be loaded.");

  return (
    <Screen>
      <Modal
        visible={pickerOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setPickerOpen(false)}
      >
        <Pressable
          className="flex-1 justify-end bg-stone/60"
          accessibilityRole="button"
          accessibilityLabel="Close member list"
          onPress={() => setPickerOpen(false)}
        >
          <Pressable className="max-h-[75%] rounded-t-card bg-ivory px-screen pb-10 pt-5">
            <Text className="font-display text-2xl text-stone">
              Who will verify this seva
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              Choose the Community Head, Tech Admin, or President who saw you
              serve. Only they are notified.
            </Text>

            <View className="mt-4 min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
              <Ionicons name="search" size={19} color={tokens.colors.stoneMuted} />
              <TextInput
                className="ml-3 flex-1 py-3 font-sans text-base text-stone"
                accessibilityLabel="Search members"
                placeholder="Search by name"
                placeholderTextColor={tokens.colors.stoneMuted}
                autoCapitalize="words"
                autoCorrect={false}
                value={search}
                onChangeText={setSearch}
              />
            </View>

            <View className="mt-4 overflow-hidden rounded-card border border-border bg-white">
              {verifiers.isLoading ? (
                <Text className="p-card text-center font-sans text-base text-stoneMuted">
                  Loading members…
                </Text>
              ) : matchingVerifiers.length ? (
                matchingVerifiers.map((person, index) => {
                  const selected = person.id === verifierId;
                  return (
                    <Pressable
                      key={person.id}
                      className={`min-h-touch flex-row items-center px-card py-3 ${
                        index < matchingVerifiers.length - 1
                          ? "border-b border-border"
                          : ""
                      } ${selected ? "bg-indigoSoft" : ""}`}
                      accessibilityRole="radio"
                      accessibilityState={{ selected }}
                      accessibilityLabel={`${person.name}, ${roleLabel(person.role_name)}`}
                      onPress={() => {
                        setVerifierId(person.id);
                        setPickerOpen(false);
                      }}
                    >
                      <Avatar
                        name={person.name}
                        photoUrl={person.photo_url}
                        size="small"
                        tone={selected ? "indigo" : "peacock"}
                      />
                      <View className="ml-3 min-w-0 flex-1">
                        <Text
                          className="font-sans-bold text-base text-stone"
                          numberOfLines={1}
                        >
                          {person.name}
                        </Text>
                        <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                          {roleLabel(person.role_name)}
                        </Text>
                      </View>
                      <Ionicons
                        name={selected ? "radio-button-on" : "radio-button-off"}
                        size={21}
                        color={selected ? tokens.colors.indigo : tokens.colors.border}
                      />
                    </Pressable>
                  );
                })
              ) : (
                <Text className="p-card text-center font-sans text-sm text-stoneMuted">
                  {search
                    ? "No member matches that name."
                    : "No Community Head, Tech Admin, or President is available yet."}
                </Text>
              )}
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-display text-xl text-stone">
          Register your seva
        </Text>
        <Text className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted">
          Scan the temple QR or choose the seva, set the day and time, and pick
          the member who will verify it. Times are temple time ({zone}).
        </Text>
      </View>

      {error ? <FormError message={error} /> : null}

      <Pressable
        className="mb-section min-h-touch flex-row items-center rounded-card bg-indigo px-card py-3"
        accessibilityRole="button"
        accessibilityLabel="Scan the temple seva QR code"
        onPress={() => {
          setScanLocked(false);
          setCameraError(null);
          setFormError(null);
          setScanMode(true);
        }}
      >
        <Ionicons
          name={qrToken ? "shield-checkmark" : "qr-code"}
          size={23}
          color={tokens.colors.marigoldSoft}
        />
        <View className="ml-3 flex-1">
          <Text className="font-sans-bold text-base text-white">
            {qrToken ? "Temple QR ready" : "Scan temple seva QR"}
          </Text>
          <Text className="font-sans text-xs text-white">
            {qrToken
              ? "The temple code identifies this seva"
              : "Or choose from the list below"}
          </Text>
        </View>
      </Pressable>

      {scanMode ? (
        <View className="mb-section overflow-hidden rounded-card border border-border bg-indigo">
          {isIosSimulator ? (
            <View className="px-card py-6">
              <Text className="text-center font-sans-bold text-base text-white">
                Test the QR flow in this simulator
              </Text>
              <View className="mt-4 gap-2">
                {qrTokens.isLoading ? (
                  <Text className="text-center font-sans text-sm text-white">
                    Loading temple codes…
                  </Text>
                ) : qrTokens.data?.length ? (
                  qrTokens.data.map((serviceType) => (
                    <Pressable
                      key={serviceType.id}
                      className="min-h-touch justify-center rounded-button bg-white px-4"
                      accessibilityRole="button"
                      accessibilityLabel={`Test ${serviceType.name} QR code`}
                      onPress={() => acceptScannedCode(serviceType.qr_token)}
                    >
                      <Text className="text-center font-sans-bold text-sm text-indigo">
                        Test {serviceType.name} QR
                      </Text>
                    </Pressable>
                  ))
                ) : (
                  <Text className="text-center font-sans text-sm leading-5 text-white">
                    Temple QR codes are visible to Community Heads, Tech Admins,
                    and the President only.
                  </Text>
                )}
              </View>
            </View>
          ) : !permission ? (
            <Text className="p-card text-center font-sans text-white">
              Preparing the camera…
            </Text>
          ) : !permission.granted ? (
            <View className="items-center px-card py-8">
              <Text className="text-center font-sans-bold text-base text-white">
                Camera access is needed to scan temple seva QR codes.
              </Text>
              <View className="mt-4 w-full">
                <Button
                  onPress={() =>
                    void (permission.canAskAgain
                      ? requestPermission()
                      : Linking.openSettings())
                  }
                >
                  {permission.canAskAgain ? "Allow camera" : "Open Settings"}
                </Button>
              </View>
            </View>
          ) : cameraError ? (
            <View className="items-center px-card py-8">
              <Text className="text-center font-sans-bold text-base text-white">
                The camera could not start.
              </Text>
            </View>
          ) : (
            <CameraView
              style={{ height: 280 }}
              facing="back"
              barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
              onBarcodeScanned={({ data }) => acceptScannedCode(data)}
              onMountError={() => setCameraError("camera")}
            />
          )}
        </View>
      ) : null}

      {!qrToken ? (
        <>
          <SectionHeader title="Which seva" />
          <View className="mb-section">
            <ServiceTypePicker
              serviceTypes={dashboard.data?.serviceTypes ?? []}
              selectedTypeId={customSelected ? null : serviceTypeId}
              customSelected={customSelected}
              onSelectType={(id) => {
                setCustomSelected(false);
                setServiceTypeId(id);
              }}
              onSelectCustom={() => {
                setCustomSelected(true);
                setServiceTypeId(null);
              }}
            />
            {customSelected ? (
              <CustomServiceInput
                value={customName}
                onChangeText={setCustomName}
                placeholder="Describe the seva you will do"
              />
            ) : null}
          </View>
        </>
      ) : null}

      <SectionHeader title={`When (${zone})`} />
      <View className="mb-3">
        <DateField label="Day" value={day} onChange={setDay} />
      </View>
      <View className="mb-2 flex-row gap-3">
        <TimeField label="Start" value={startTime} onChange={setStartTime} />
        <TimeField label="End" value={endTime} onChange={setEndTime} />
      </View>
      <Text className="mb-section font-sans text-xs leading-4 text-stoneMuted">
        Register seva happening now, later today, or any day ahead. Seva that
        has already finished cannot be registered.
      </Text>

      <SectionHeader title="Where" />
      <View className="mb-section min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="font-sans text-base text-stone"
          accessibilityLabel="Where you are serving"
          value={locationText}
          onChangeText={setLocationText}
          placeholder="ISKCON Chicago Temple"
          placeholderTextColor={tokens.colors.stoneMuted}
        />
      </View>

      <SectionHeader title="Who will verify it" />
      <Pressable
        className="mb-section min-h-touch flex-row items-center rounded-button border border-border bg-white px-4 py-2"
        accessibilityRole="button"
        accessibilityLabel={
          selectedVerifier
            ? `Verifier: ${selectedVerifier.name}. Tap to change.`
            : "Choose a member to verify this seva"
        }
        onPress={() => setPickerOpen(true)}
      >
        {selectedVerifier ? (
          <>
            <Avatar
              name={selectedVerifier.name}
              photoUrl={selectedVerifier.photo_url}
              size="small"
              tone="indigo"
            />
            <View className="ml-3 min-w-0 flex-1">
              <Text
                className="font-sans-bold text-base text-stone"
                numberOfLines={1}
              >
                {selectedVerifier.name}
              </Text>
              <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                {roleLabel(selectedVerifier.role_name)}
              </Text>
            </View>
          </>
        ) : (
          <Text className="flex-1 font-sans text-base text-stoneMuted">
            Choose a member
          </Text>
        )}
        <Ionicons name="chevron-down" size={21} color={tokens.colors.indigo} />
      </Pressable>

      <Button
        icon="shield-checkmark-outline"
        disabled={register.isPending}
        onPress={submit}
      >
        {register.isPending ? "Registering…" : "Register your seva"}
      </Button>
    </Screen>
  );
}
