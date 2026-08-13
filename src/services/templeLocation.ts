import * as Location from "expo-location";
import * as TaskManager from "expo-task-manager";

import { sendTempleArrivalReminder } from "./notifications";
import { usePrototypeSession } from "../store/usePrototypeSession";

export const ISKCON_CHICAGO_LOCATION = {
  address: "1716 W Lunt Ave, Chicago, IL 60626",
  latitude: 42.00935,
  longitude: -87.67305,
  radiusMeters: 75,
} as const;

const EARTH_RADIUS_METERS = 6_371_000;
const MAX_AUTOMATIC_ACCURACY_METERS = 75;
const TEMPLE_GEOFENCE_TASK = "iskcon-chicago-temple-geofence";

if (!TaskManager.isTaskDefined(TEMPLE_GEOFENCE_TASK)) {
  TaskManager.defineTask(TEMPLE_GEOFENCE_TASK, async ({ data, error }) => {
    if (error || !data) return;

    const event = data as {
      eventType: Location.GeofencingEventType;
      region: Location.LocationRegion;
    };
    const state = usePrototypeSession.getState();
    if (!state.activeUserId) return;

    if (event.eventType === Location.GeofencingEventType.Enter) {
      await sendTempleArrivalReminder(state.activeUserId);
    }
  });
}

function degreesToRadians(degrees: number) {
  return (degrees * Math.PI) / 180;
}

export function distanceInMeters(
  first: { latitude: number; longitude: number },
  second: { latitude: number; longitude: number },
) {
  const latitudeDelta = degreesToRadians(second.latitude - first.latitude);
  const longitudeDelta = degreesToRadians(second.longitude - first.longitude);
  const firstLatitude = degreesToRadians(first.latitude);
  const secondLatitude = degreesToRadians(second.latitude);
  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(firstLatitude) *
      Math.cos(secondLatitude) *
      Math.sin(longitudeDelta / 2) ** 2;

  return (
    2 *
    EARTH_RADIUS_METERS *
    Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
  );
}

export type TempleProximity = {
  accuracyMeters: number | null;
  distanceMeters: number;
  isAccurateEnough: boolean;
  isInside: boolean;
};

export function evaluateTempleProximity(input: {
  latitude: number;
  longitude: number;
  accuracy: number | null;
}): TempleProximity {
  const distanceMeters = distanceInMeters(input, ISKCON_CHICAGO_LOCATION);
  const isAccurateEnough =
    input.accuracy === null || input.accuracy <= MAX_AUTOMATIC_ACCURACY_METERS;

  return {
    accuracyMeters: input.accuracy,
    distanceMeters,
    isAccurateEnough,
    isInside:
      isAccurateEnough &&
      distanceMeters <= ISKCON_CHICAGO_LOCATION.radiusMeters,
  };
}

export async function getCurrentTempleProximity() {
  const location = await Location.getCurrentPositionAsync({
    accuracy: Location.Accuracy.High,
    mayShowUserSettingsDialog: true,
  });

  return evaluateTempleProximity(location.coords);
}

export async function startTempleGeofencingIfAllowed() {
  const backgroundPermission = await Location.getBackgroundPermissionsAsync();
  if (!backgroundPermission.granted) return false;

  const backgroundLocationAvailable =
    await Location.isBackgroundLocationAvailableAsync();
  if (!backgroundLocationAvailable) return false;

  await Location.startGeofencingAsync(TEMPLE_GEOFENCE_TASK, [
    {
      identifier: "iskcon-chicago-lunt-avenue",
      latitude: ISKCON_CHICAGO_LOCATION.latitude,
      longitude: ISKCON_CHICAGO_LOCATION.longitude,
      radius: ISKCON_CHICAGO_LOCATION.radiusMeters,
      notifyOnEnter: true,
      notifyOnExit: false,
    },
  ]);

  return true;
}
