import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/** Register (or refresh) a device's APNs token for the current user. */
export class RegisterDeviceTokenDto {
  /** Hex-encoded APNs device token. */
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  token!: string;

  @IsOptional()
  @IsIn(['ios'])
  platform?: string;

  /** Which APNs host this token belongs to. */
  @IsOptional()
  @IsIn(['production', 'sandbox'])
  environment?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  bundleId!: string;
}

/** Drop a device token (sign-out). */
export class UnregisterDeviceTokenDto {
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  token!: string;
}
