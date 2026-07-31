/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { WelcomeScreen } from "../WelcomeScreen";

describe("WelcomeScreen", () => {
  it("opens the visual prototype from the primary action", async () => {
    const onEnter = jest.fn();

    const { getByRole } = await render(<WelcomeScreen onEnter={onEnter} />);

    await fireEvent.press(getByRole("button", { name: "Preview the app" }));

    expect(onEnter).toHaveBeenCalledTimes(1);
  });
});
