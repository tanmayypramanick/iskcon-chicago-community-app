import { create } from "zustand";

export type AccessRole = "president" | "tech" | "core" | "devotee";

type PrototypeSession = {
  isAuthenticated: boolean;
  role: AccessRole;
  authenticate: () => void;
  signOut: () => void;
  setRole: (role: AccessRole) => void;
};

export const usePrototypeSession = create<PrototypeSession>((set) => ({
  isAuthenticated: false,
  role: "devotee",
  authenticate: () => set({ isAuthenticated: true }),
  signOut: () => set({ isAuthenticated: false, role: "devotee" }),
  setRole: (role) => set({ role }),
}));
