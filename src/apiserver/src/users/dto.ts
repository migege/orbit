import { IsBoolean, IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email!: string;

  @IsOptional()
  @IsString()
  name?: string;

  /** Omit to have a strong password generated and returned once. */
  @IsOptional()
  @IsString()
  @MinLength(6)
  password?: string;

  /** Reset the password of an existing user instead of failing on conflict. */
  @IsOptional()
  @IsBoolean()
  force?: boolean;
}
