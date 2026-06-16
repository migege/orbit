import { BadRequestException, Injectable, PipeTransform } from '@nestjs/common';
import { toUuid } from '@orbit/shared';

/** Resolves a route `:id` that may be a base62 public id (the short form used
 *  in shareable URLs) or a raw UUID, to the canonical UUID the service layer
 *  queries by. Rejects input that is neither. */
@Injectable()
export class Base62UuidPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    try {
      return toUuid(value);
    } catch {
      throw new BadRequestException('invalid id');
    }
  }
}
