export const db = {
  async query(name: string) {
    if (name === "admin") {
      return { ok: true };
    }
    return { ok: false };
  },
};
