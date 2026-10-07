import { db } from "./database";

export class UserService {
  async authenticate(name: string) {
    if (!name) {
      throw new Error("empty");
    }
    const row = await db.query(name);
    return row;
  }
}

export function login(u: string) {
  const s = new UserService();
  return s.authenticate(u);
}
