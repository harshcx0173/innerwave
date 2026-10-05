const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

function istParts(value: Date) {
  const shifted = new Date(value.getTime() + IST_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(), minute: shifted.getUTCMinutes(),
  };
}

function clock(hour: number, minute: number) {
  const suffix = hour >= 12 ? "PM" : "AM";
  const twelve = hour % 12 || 12;
  return `${twelve}:${String(minute).padStart(2, "0")} ${suffix}`;
}

export function formatChatTime(createdAt: string, now = new Date()) {
  const value = new Date(createdAt);
  const age = Math.max(0, now.getTime() - value.getTime());
  if (age < 60 * 60 * 1000) return `${Math.max(1, Math.floor(age / 60000))}m`;
  const current = istParts(now);
  const created = istParts(value);
  const todaySerial = Date.UTC(current.year, current.month - 1, current.day) / 86400000;
  const createdSerial = Date.UTC(created.year, created.month - 1, created.day) / 86400000;
  const formattedClock = clock(created.hour, created.minute);
  if (todaySerial === createdSerial) return formattedClock;
  if (todaySerial - createdSerial === 1) return `Yesterday ${formattedClock}`;
  return `${String(created.day).padStart(2, "0")}/${String(created.month).padStart(2, "0")}/${created.year} ${formattedClock}`;
}
