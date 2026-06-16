import { SetMetadata } from '@nestjs/common';

/**
 * Marks a route that may authenticate via a `?access_token=` query parameter.
 * Only the SSE stream needs this (EventSource cannot set request headers); every
 * other route must use the `Authorization` header so a long-lived bearer token
 * never leaks into proxy/CDN access logs or the Referer header.
 */
export const ALLOW_QUERY_TOKEN = 'allowQueryToken';
export const AllowQueryToken = () => SetMetadata(ALLOW_QUERY_TOKEN, true);
