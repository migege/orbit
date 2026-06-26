export * from './enums';
export * from './events';
export * from './dto';
export * from './codec';

/** Hard cap on a single user prompt / turn message, in characters. An oversized input
 *  freezes the web and macOS clients — one giant text node lays out synchronously on the
 *  main thread — so the composer blocks it client-side and the server rejects it (400) as a
 *  backstop. Very large content belongs in an uploaded file the agent reads, not a prompt. */
export const MAX_PROMPT_CHARS = 50_000;
