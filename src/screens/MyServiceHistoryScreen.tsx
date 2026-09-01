import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Text, View } from "react-native";

import {
  GroupLabel,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { MySevaSummary } from "../features/profile/sevaHoursCard";
import {
  RegisteredSevaCard,
  ServiceCard,
  WeeklySevaCard,
} from "../features/services/components";
import { useServiceDashboard } from "../features/services/hooks";
import {
  completedRegistrations,
  myUnverifiedRegistrations,
  registrationInstanceIds,
  sevaTiming,
  upcomingRegistrations,
} from "../features/services/registrations";
import {
  completedServices,
  didServe,
  isSevaConfirmedServed,
  myUpcomingOneTime,
  myWeeklySeva,
} from "../features/services/selectors";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "MyServiceHistory">;

export function MyServiceHistoryScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const weekly = dashboard.data && activeUserId ? myWeeklySeva(dashboard.data, activeUserId) : [];
  const upcoming = dashboard.data && activeUserId ? myUpcomingOneTime(dashboard.data, activeUserId) : [];
  // Registered seva is the devotee's own record of what they served, so this
  // screen would be missing most of their history without it.
  const scope = { userId: activeUserId, seesEveryone: false };
  const registrationInstances = dashboard.data
    ? registrationInstanceIds(dashboard.data)
    : new Set<string>();
  const registeredUpcoming = dashboard.data
    ? upcomingRegistrations(dashboard.data, scope).filter(
        (row) => row.status === "verified",
      )
    : [];
  const registeredWaiting = dashboard.data
    ? myUnverifiedRegistrations(dashboard.data, activeUserId)
    : [];
  const registeredCompleted = dashboard.data
    ? completedRegistrations(dashboard.data, scope)
    : [];
  // "What I offered", so the same rule the Seva tab applies from the same
  // helper: a place this devotee gave away is not theirs, and neither is a
  // morning somebody recorded them absent or excused for. Reading
  // `currentUserAssignment` directly asked neither question, and this screen
  // was the one place a devotee could still see an absence as their own seva.
  const mine = dashboard.data && activeUserId
    ? completedServices(dashboard.data).filter(
        (service) =>
          didServe(service, activeUserId) &&
          !registrationInstances.has(service.id),
      )
    : [];
  // The same rule as the Seva tab: a seva nobody has confirmed served is not
  // history yet, so it is shown as waiting rather than counted as completed.
  // Its hours are unaffected either way — only its place in these lists is.
  const completed = mine.filter(isSevaConfirmedServed);
  const awaitingConfirmation = mine.filter(
    (service) => !isSevaConfirmedServed(service),
  );
  const completedWeeklyIds = new Set(
    completed.flatMap((service) => service.template_id ? [service.template_id] : []),
  );
  const completedWeekly = dashboard.data?.recurringTemplates.filter((template) => completedWeeklyIds.has(template.id)) ?? [];
  const completedOneTime = completed.filter((service) => !service.template_id);
  // One section now, so one "See all" counting both groups rather than two
  // that each appeared on their own.
  const seeAllUpcoming = weekly.length + upcoming.length > 4;

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Your offerings">My seva</ScreenTitle>

      {/* The hours first, then what they were offered to. This is the page a
          devotee opens to read their own seva, so the summary the temple took
          off the Profile tab belongs at the top of it. */}
      <MySevaSummary userId={activeUserId} />

      {/* One section, two groups — the same shape as the Seva tab. "My weekly
          seva" and "Upcoming seva" were two answers to one question, and the
          temple asked for one. */}
      <SectionHeader
        title="My upcoming seva"
        action={seeAllUpcoming ? "See all" : undefined}
        onAction={
          seeAllUpcoming
            ? () => navigation.navigate("SevaList", { kind: "my_upcoming" })
            : undefined
        }
      />
      <View className="mb-section gap-3">
        {weekly.length ? <GroupLabel>Weekly seva</GroupLabel> : null}
        {weekly.slice(0, 4).map((template) => (
          <WeeklySevaCard key={template.id} template={template} onPress={() => navigation.navigate("WeeklySevaDetail", { templateId: template.id })} />
        ))}

        {registeredUpcoming.length || upcoming.length ? (
          <GroupLabel>One-off seva</GroupLabel>
        ) : null}
        {registeredUpcoming.map((row) => (
          <RegisteredSevaCard
            key={row.id}
            registration={row}
            timing="upcoming"
            isMine
            onPress={() =>
              navigation.navigate("SevaRegistrationDetail", {
                verificationId: row.id,
              })
            }
          />
        ))}
        {upcoming.slice(0, 4).map((service) => (
          <ServiceCard key={service.id} service={service} onPress={() => navigation.navigate("ServiceDetail", { serviceId: service.id })} />
        ))}

        {weekly.length || registeredUpcoming.length || upcoming.length ? null : (
          <View className="rounded-card border border-border bg-white p-card">
            <Text className="font-sans text-base text-stoneMuted">
              No seva is assigned to you.
            </Text>
          </View>
        )}
      </View>

      {registeredWaiting.length || awaitingConfirmation.length ? (
        <>
          <SectionHeader
            title="Waiting to be verified"
            subtitle={
              // Only true of seva already completed and awaiting the
              // confirmation. A registration nobody has answered yet has no
              // assignment, no instance and no hours anywhere, so the old
              // wording — "your hours are counted already" — was a promise to
              // the one devotee it was least true for.
              awaitingConfirmation.length && !registeredWaiting.length
                ? "Your hours are counted already. This is only the confirmation."
                : "Nothing here counts until the member you asked confirms it."
            }
          />
          <View className="mb-section gap-3">
            {awaitingConfirmation.map((service) => (
              <ServiceCard
                key={service.id}
                service={service}
                onPress={() =>
                  navigation.navigate("ServiceDetail", {
                    serviceId: service.id,
                  })
                }
              />
            ))}
            {registeredWaiting.map((row) => (
              <RegisteredSevaCard
                key={row.id}
                registration={row}
                timing={sevaTiming(row)}
                isMine
                onPress={() =>
                  navigation.navigate("SevaRegistrationDetail", {
                    verificationId: row.id,
                  })
                }
              />
            ))}
          </View>
        </>
      ) : null}

      <SectionHeader
        title="Completed seva"
        action={completedWeekly.length + completedOneTime.length > 4 ? "See all" : undefined}
        onAction={completedWeekly.length + completedOneTime.length > 4 ? () => navigation.navigate("SevaList", { kind: "my_seva" }) : undefined}
      />
      <View className="gap-3">
        {registeredCompleted.slice(0, 4).map((row) => (
          <RegisteredSevaCard
            key={row.id}
            registration={row}
            timing="finished"
            isMine
            onPress={() =>
              navigation.navigate("SevaRegistrationDetail", {
                verificationId: row.id,
              })
            }
          />
        ))}
        {completedWeekly.slice(0, 2).map((template) => (
          <WeeklySevaCard key={template.id} template={template} onPress={() => navigation.navigate("WeeklySevaDetail", { templateId: template.id })} />
        ))}
        {completedOneTime.slice(0, Math.max(0, 4 - Math.min(2, completedWeekly.length))).map((service) => (
          <ServiceCard key={service.id} service={service} onPress={() => navigation.navigate("ServiceDetail", { serviceId: service.id })} />
        ))}
        {!completedWeekly.length && !completedOneTime.length ? (
          <View className="rounded-card border border-border bg-white p-card">
            <Text className="font-sans text-base text-stoneMuted">
              Completed seva will be kept here as your personal history.
            </Text>
          </View>
        ) : null}
      </View>
    </Screen>
  );
}
