import { initializeApp, getApps, getApp } from "firebase/app";
import { getDatabase } from "firebase/database";

// Instead of passing all credentials via .env mapping to Next.js right away,
// We hardcode the URL used by the Godot environment or use NEXT_PUBLIC env vars.
const firebaseConfig = {
  // Since we only need realtime database and no auth strict rules currently:
  databaseURL: "https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app"
};

const app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
export const db = getDatabase(app);
