// Only the 10 national digits are typed; the +1 is fixed. A leading 1 is
// always a country code (US area codes never start with 1), so it is dropped
// whether typed out of habit or pasted as part of "+1 (415) 555-2671".
export function nationalDigits(value) {
  return (value || "").replace(/\D/g, "").replace(/^1/, "").slice(0, 10);
}

// 4155552671 -> (415) 555-2671, applied progressively while typing
export function formatNational(digits) {
  if (digits.length <= 3) {
    return digits;
  }
  if (digits.length <= 6) {
    return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
  }
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}
